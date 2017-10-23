
abstract type AbstractCodeCtx end

mutable struct CodeCtx <: AbstractCodeCtx
    builder::LLVM.Builder
    mod::LLVM.Module
    code_info::CodeInfo
    result_type::DataType
    name::String
    argtypes
    nargs::Int
    func::LLVM.Function
    extern::Dict{Symbol, Any}
    builtin::Dict{Symbol, LLVM.Function}
    datatype::Dict{Symbol, Any}
    current_scope::CurrentScope
    slots::Vector{LLVM.Value}
    ssas::Dict{Int, LLVM.Value}
    meta::Dict{Symbol, Any}
    labels::Dict{Int, Any}
    CodeCtx(mod::LLVM.Module, ci::CodeInfo, result_type::DataType, name, argtypes) = 
        new(LLVM.Builder(ctx),
            mod, 
            ci,
            result_type,
            name,
            argtypes,
            length(argtypes.parameters))
end

function CodeCtx(ci::CodeInfo, result_type::DataType, name, argtypes)
    cg = CodeCtx(LLVM.Module("JuliaCodeGenModule", ctx), ci, result_type, name, argtypes)
    global M = cg.mod
    cg.builtin = setup_builtins!(cg)
    cg.extern = setup_externs!(cg.mod)
    cg.datatype = setup_types!(cg)
    global D = cg.datatype
    cg.slots = Vector{LLVM.Value}(length(ci.slotnames))
    cg.ssas = Dict{Int, LLVM.Value}()
    cg.labels = Dict{Int, Any}()
    cg.current_scope = CurrentScope()
    return cg
end

function CodeCtx(orig_cg::CodeCtx, ci::CodeInfo, result_type::DataType, name, argtypes)
    cg = CodeCtx(orig_cg.mod, ci, result_type, name, argtypes)
    cg.builtin = orig_cg.builtin
    cg.extern = orig_cg.extern
    cg.datatype = orig_cg.datatype
    cg.slots = Vector{LLVM.Value}(length(ci.slotnames))
    cg.ssas = Dict{Int, LLVM.Value}()
    cg.labels = Dict{Int, Any}()
    cg.current_scope = CurrentScope()
    return cg
end

Base.show(io::IO, cg::CodeCtx) = print(io, "CodeCtx")

current_scope(cg::CodeCtx) = cg.current_scope
function new_scope(f, cg::CodeCtx)
    open_scope!(current_scope(cg))
    f()
    pop!(current_scope(cg))
end

function create_entry_block_allocation(cg::CodeCtx, fn::LLVM.Function, typ, varname::String)
    local alloc
    LLVM.Builder(ctx) do builder
        # Set the builder at the start of the function
        entry_block = LLVM.entry(fn)
        if isempty(LLVM.instructions(entry_block))
            LLVM.position!(builder, entry_block)
        else
            LLVM.position!(builder, first(LLVM.instructions(entry_block)))
        end
        alloc = LLVM.alloca!(builder, typ)
    end
    return alloc
end


function codegen(@nospecialize(fun), @nospecialize(argtypes); optimize_lowering = true) 
    ci, dt = code_typed(fun, argtypes, optimize = optimize_lowering)[1]
    funname = string(Base.function_name(fun)) # good link: typeof(f).name.mt.name; https://stackoverflow.com/questions/38819327/given-a-function-object-how-do-i-find-its-name-and-module
    cg = CodeCtx(ci, dt, funname, argtypes)
    return codegen!(cg)
end

#
# Main entry
#
function codegen!(cg::CodeCtx)
    ci = cg.code_info
    argtypes = LLVMType[llvmtype(p) for p in cg.argtypes.parameters]
    for i in 1:length(argtypes)
        @show argtypes[i]
        if isa(argtypes[i], LLVM.VoidType)
            argtypes[i] = int32_t
        end
    end
    func_type = LLVM.FunctionType(llvmtype(cg.result_type), argtypes)
    cg.func = LLVM.Function(cg.mod, cg.name, func_type)
    cg.nargs = length(argtypes)
    LLVM.linkage!(cg.func, LLVM.API.LLVMExternalLinkage)
    entry = LLVM.BasicBlock(cg.func, "entry", ctx)
    LLVM.position!(cg.builder, entry)
    for (i, param) in enumerate(LLVM.parameters(cg.func))
        argname = string(ci.slotnames[i + 1])
        if !isa(LLVM.llvmtype(param), LLVM.VoidType)
            @show argname, LLVM.llvmtype(param)
            alloc = create_entry_block_allocation(cg, cg.func, LLVM.llvmtype(param), argname)
            LLVM.store!(cg.builder, param, alloc)
            current_scope(cg)[argname] = alloc
        end
    end
    for i in cg.nargs+2:length(ci.slotnames)
        varname = string(ci.slotnames[i])
        vartype = llvmtype(ci.slottypes[i])
        alloc = LLVM.alloca!(cg.builder, vartype)
        current_scope(cg)[varname] = alloc
    end
    for node in ci.code
        codegen!(cg, node)
    end
    # LLVM.verify(func)
    # LLVM.dispose(cg.builder)  # ?? something different for multiple funs 
    return cg.mod
end

#
# Expressions
#
function codegen!(cg::CodeCtx, e::Expr)
    # Slow dispatches here but easy to write and to customize
    codegen!(cg, Val(e.head), e.args, e.typ) 
end

#
# Variable assignment and reading
#
function codegen!(cg::CodeCtx, v::SlotNumber) 
    varname = string(cg.code_info.slotnames[v.id])
    # cg.slots[v.id]
    V = get(current_scope(cg), varname, nothing)
    V == nothing && error("did not find variable $(varname)")
    return LLVM.load!(cg.builder, V, varname)
end

function codegen!(cg::CodeCtx, ::Val{:(=)}, args, typ)
    result = codegen!(cg, args[2])
    if isa(args[1], SlotNumber)
        varname = string(cg.code_info.slotnames[args[1].id])
        V = get(current_scope(cg), varname, nothing)
        V == nothing && error("unknown variable name $(varname)")
        LLVM.store!(cg.builder, result, V)
        # LLVM.name!(result, varname)
        unboxed_result = emit_unbox!(cg, result, typ)
        cg.slots[args[1].id] = unboxed_result
        return unboxed_result
    end
    if isa(args[1], SSAValue)
        unboxed_result = emit_unbox!(cg, result, typ)
        cg.ssas[args[1].id] = unboxed_result
        return unboxed_result
    end
end

function codegen!(cg::CodeCtx, f::GlobalRef) 
    if haskey(LLVM.functions(cg.mod), string(f.name))
        return LLVM.functions(cg.mod)[string(f.name)]
    end
    return codegen!(cg, Int32(0)) # BROKEN
end

function codegen!(cg::CodeCtx, x::QuoteNode) 
    return codegen!(cg, Int32(0)) # BROKEN
    # return codegen!(cg, x.value) 
end


#
# Function calls
#
function codegen!(cg::CodeCtx, ::Val{:call}, args, typ)
    llvmargs = LLVM.Value[]
    for v in args[2:end]
        push!(llvmargs, codegen!(cg, v))
    end
    @show args[1], typ
    fun = eval(args[1])
    if isa(fun, Core.IntrinsicFunction)
        return emit_intrinsic!(cg, args[1].name, llvmargs)
    end
    if isa(fun, Core.Builtin)
        return emit_unbox!(cg, emit_builtin!(cg, args[1].name, llvmargs), typ)
    end
    name = string(args[1])
    error("Function $name not supported.")
end

function codegen!(cg::CodeCtx, ::Val{:invoke}, args, typ)
    # name = string(Base.function_name(args[1]))
    name = string(args[2])
    println("Invoking... $name")
    if haskey(LLVM.functions(cg.mod), name)
        func = LLVM.functions(cg.mod)[name]
    else
        argtypes = Tuple{args[1].specTypes.parameters[2:end]...}
        fun = eval(args[2])
        ci, dt = code_typed(fun, argtypes, optimize = true)[1]
        newcg = CodeCtx(cg, ci, dt, name, argtypes)
        codegen!(newcg)
        func = newcg.func
    end
    llvmargs = LLVM.Value[]
    for v in args[3:end]
        push!(llvmargs, codegen!(cg, v))
    end
    
    return LLVM.call!(cg.builder, func, llvmargs)
end

function codegen!(cg::CodeCtx, ::Val{:return}, args, typ)
    if length(args) == 1
        res = codegen!(cg, args[1])
        if LLVM.llvmtype(res) != llvmtype(cg.result_type)
            res = emit_unbox!(cg, res, cg.result_type)
        end
        LLVM.ret!(cg.builder, res)
    else
        LLVM.ret!(cg.builder)
    end
end

#
# Constants and types
#
codegen!(cg::CodeCtx, x::T) where T <: Base.IEEEFloat =
    LLVM.ConstantFP(llvmtype(T), x)

codegen!(cg::CodeCtx, x::T) where T <: Base.BitInteger =
    LLVM.ConstantInt(llvmtype(T), x)

codegen!(cg::CodeCtx, x::Bool) =
    LLVM.ConstantInt(bool_t, Int8(x))

function codegen!(cg::CodeCtx, s::String)
    # strinst = globalstring!(builder, s)
    gs = globalstring_ptr!(cg.builder, s)
    return LLVM.call!(cg.builder, cg.extern[:jl_pchar_to_string_f], LLVM.Value[gs, codegen!(cg, Int32(length(s)+1))])
end

# I'm not sure these are appropriate:
# codegen!(cg::CodeCtx, ::Type{T}) where T <: Base.IEEEFloat =
#     llvmtype(T)

# codegen!(cg::CodeCtx, ::Type{T}) where T <: Base.BitInteger =
#     llvmtype(T)

# The following would need to create the appropriate structures in memory
function codegen!(cg::CodeCtx, ::Type{Array{T,N}}) where {T,N}
    typ = LLVM.load!(cg.builder, cg.extern[:jl_array_type_g])
    # bctyp = LLVM.bitcast!(cg.builder, typ, jl_value_t_ptr)
    return LLVM.call!(cg.builder, cg.extern[:jl_apply_array_type_f], LLVM.Value[typ, codegen!(cg, UInt32(N))])
    # arraytype = codegen!(cg, Val(:extcall), "jl_apply_array_type", Any, [T, N])
end
#   %9 = load %struct._jl_datatype_t*, %struct._jl_datatype_t** @jl_float64_type, align 8
#   %10 = bitcast %struct._jl_datatype_t* %9 to %struct._jl_value_t*
#   %11 = call %struct._jl_value_t* @jl_apply_array_type(%struct._jl_value_t* %10, i64 1)

# codegen!(cg::CodeCtx, s::String) where T = ??
# use jl_cstr_to_string or jl_pchar_to_string

#
# Miscellaneous
#
codegen!(cg::CodeCtx, v::SSAValue) = cg.ssas[v.id]

codegen!(cg::CodeCtx, ::Val{:meta}, args, typ) = nothing

codegen!(cg::CodeCtx, ::LineNumberNode) = nothing

codegen!(cg::CodeCtx, ::NewvarNode) = nothing


#
# ccall
#
function codegen!(cg::CodeCtx, ::Val{:foreigncall}, args, typ)
    name = args[1].value
    if haskey(cg.extern, name)
        func = cg.extern[name]
    else
        func = extern!(cg.mod, name, llvmtype(args[2]), llvmtype.(collect(args[3])))
    end
    llvmargs = LLVM.Value[]
    for v in args[6:end]
        push!(llvmargs, codegen!(cg, v))
    end
    
    return LLVM.call!(cg.builder, func, llvmargs)
end

function codegen!(cg::CodeCtx, ::Val{:extcall}, name, rettype, args)
    llvmargs = LLVM.Value[]
    llvmargtypes = LLVM.Value[]
    for v in args
        push!(llvmargs, llvmtype(typeof(v)))
        push!(llvmargs, codegen!(cg, v))
    end
    
    func_type = LLVM.FunctionType(llvmtype(rettype), llvmargtypes)
    func = LLVM.Function(cg.mod, name, func_type)
    LLVM.linkage!(func, LLVM.API.LLVMExternalLinkage)

    return LLVM.call!(cg.builder, func, llvmargs)
end
#
# Control flow
#

function codegen!(cg::CodeCtx, ln::LabelNode)
    if !haskey(cg.labels, ln.label)
        func = LLVM.parent(LLVM.position(cg.builder))
        cg.labels[ln.label] = LLVM.BasicBlock(func, "L", ctx)
    end
    if !has_terminator(position(cg.builder))
        br!(cg.builder, cg.labels[ln.label])
    end
    position!(cg.builder, cg.labels[ln.label])
end

function codegen!(cg::CodeCtx, gn::GotoNode)
    if !haskey(cg.labels, gn.label)
        func = LLVM.parent(LLVM.position(cg.builder))
        cg.labels[gn.label] = LLVM.BasicBlock(func, "L", ctx)
    end
    br!(cg.builder, cg.labels[gn.label])
end

function codegen!(cg::CodeCtx, ::Val{:gotoifnot}, args, typ)
    condv = codegen!(cg, args[1])
    if LLVM.width(LLVM.llvmtype(condv)) > 1
        condv = LLVM.trunc!(cg.builder, condv, int1_t)
    end
    func = LLVM.parent(LLVM.position(cg.builder))
    ifso = LLVM.BasicBlock(func, "if", ctx)
    ifnot = LLVM.BasicBlock(func, "L", ctx)
    cg.labels[args[2]] = ifnot
    LLVM.br!(cg.builder, condv, ifso, ifnot)
    position!(cg.builder, ifso)
end

#
# New - structure creation
#
function codegen!(cg::CodeCtx, ::Val{:new}, args, typ)
    dt = get_and_emit_datatype!(cg, args[1].name)
    res = LLVM.call!(cg.builder, cg.extern[:jl_new_struct_uninit_f], [dt])
    # set the fields
    for i in 2:length(args)
        rhs = codegen!(cg, args[i])  # need to box?
        offset = codegen!(cg, UInt32(i - 1))
        LLVM.call!(cg.builder, cg.extern[:jl_set_nth_field_f], LLVM.Value[res, offset, rhs])
    end
    return res
end

