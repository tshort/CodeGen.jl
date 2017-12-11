

"""
    codegen(fun, argtypes; optimize_lowering = true, triple = nothing, datalayout = nothing) 

Return the bitcode for `fun` with argument types `argtypes`. 
`argtypes` is a tuple type (e.g. `Tuple{Float64, Int}`).

The optional argument `optimize_lowering` determines whether 
`code_typed` uses optimization when infering types.

The optional arguments `triple` and `datalayout` are strings that 
set the LLVM triple and data layout for the module being generated.

`codegen` creates a `CodeCtx` and runs `codegen!(cg)`. 
Direct calls to that can be done for more flexibility.

The return value is an LLVM module. This can be written to a bitcode 
files with `write(mod, filepath)`. It can be optimized with
`optimize!(mod)`.
"""
function codegen(@nospecialize(fun), @nospecialize(argtypes); optimize_lowering = true, triple = nothing, datalayout = nothing) 
    ci, dt = code_typed(fun, argtypes, optimize = optimize_lowering)[1]
    @show ci
    sig = first(methods(fun, argtypes)).sig
    funname = getfunname(fun, argtypes)
    cg = CodeCtx(funname, ci, dt, argtypes, sig)
    return codegen!(cg)
end
getfunname(fun, argtypes) = string(basename(fun), "_", join(collect(argtypes.parameters), "_"))
basename(f::Function) = Base.function_name(f)
basename(m::Core.MethodInstance) = m.def.name
basename(m::Method) = m.name == :Type ? m.sig.parameters[1].parameters[1].name.name : m.name

#
# Main entry
#

"""
    codegen!(cg::CodeCtx)
    codegen!(cg::CodeCtx, ...)

This is the main function for dispatching various types of code generation.
"""
function codegen!(cg::CodeCtx)
    @info "## $(cg.name)"
    ci = cg.code_info
    lastsig(x) = last(x.parameters)
    lastsig(x::UnionAll) = lastsig(x.body)
    siglen(x) = length(x.parameters)
    siglen(x::UnionAll) = siglen(x.body)
    sigend = lastsig(cg.sig)
    # @show hasvararg = isa(sigend, UnionAll) && sigend.body <: Vararg
    hasvararg = isa(sigend, UnionAll) && sigend.body.name.name == :Vararg
    if hasvararg
        siglength = siglen(cg.sig) - 1
        argtypes = LLVMType[llvmtype(p) for p in cg.argtypes.parameters[1:siglength-1]]
        push!(argtypes, llvmtype(Tuple{cg.argtypes.parameters[siglength:end]...}))
    else
        argtypes = LLVMType[llvmtype(p) for p in cg.argtypes.parameters]
    end
    for i in 1:length(argtypes)
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
        argname = string(ci.slotnames[i + 1], "_as", i+1)
        if !isa(LLVM.llvmtype(param), LLVM.VoidType)
            alloc = LLVM.alloca!(cg.builder, LLVM.llvmtype(param), argname)
            store!(cg, param, alloc)
            cg.slotlocs[i + 1] = alloc
        end
    end
    for i in cg.nargs+2:length(ci.slotnames)
        varname = string(ci.slotnames[i], "_s", i)
        vartype = llvmtype(ci.slottypes[i])
        if !isa(vartype, LLVM.VoidType)
            alloc = LLVM.alloca!(cg.builder, vartype, varname)
            cg.slotlocs[i] = alloc
        end
    end
    for (i, node) in enumerate(ci.code)
        @debug "$(cg.name): node $i/$(length(ci.code))" node
        @show node
        codegen!(cg, node)
    end
    # LLVM.verify(cg.func)
    LLVM.dispose(cg.builder)
    return cg.mod
end

function codegen!(cg::CodeCtx, @nospecialize(fun), @nospecialize(argtypes); optimize_lowering = true) 
    ci, dt = code_typed(fun, argtypes, optimize = optimize_lowering)[1]
    @show ci
    funname = getfunname(fun, argtypes)
    sig = first(methods(fun, argtypes)).sig
    return codegen!(CodeCtx(cg, funname, ci, dt, argtypes, sig))
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

function codegen!(cg::CodeCtx, x::SlotNumber) 
    varname = string(cg.code_info.slotnames[x.id], "_s", x.id)
    # cg.slots[v.id]
    # p = get(current_scope(cg), varname, nothing)
    p = cg.slotlocs[x.id]
    p == nothing && error("did not find variable $(varname)")
    return LLVM.load!(cg.builder, p, varname*"_")
end

codegen!(cg::CodeCtx, x::SSAValue) = LLVM.load!(cg.builder, cg.ssas[x.id])

function codegen!(cg::CodeCtx, ::Val{:(=)}, args, typ)
    result = codegen!(cg, args[2])
    if isa(args[1], SlotNumber)
        varname = string(cg.code_info.slotnames[args[1].id], "_s", args[1].id)
        @debug "$(cg.name): Assigning slot $(args[1].id)" varname args[2] _typeof(cg, args[1]) _typeof(cg, args[2])
        p = cg.slotlocs[args[1].id]
        unboxed_result = emit_unbox!(cg, result, _typeof(cg, args[1]))
        if _typeof(cg, args[2]) == Union{}
            return
        end
        store!(cg, unboxed_result, p)
        cg.slots[args[1].id] = unboxed_result
        return unboxed_result
    end
    if isa(args[1], SSAValue)
        t = _typeof(cg, args[2])
        # if !isconcrete(t) # || sizeof(t) == 0
        #     return
        # end
        @debug "$(cg.name): Assigning SSA $(args[1].id)" typ llvmtype(_typeof(cg, args[1]))
        @info "$(cg.name): Assigning SSA $(args[1].id) $typ $result $(llvmtype(_typeof(cg, args[1])))"
        dump(args)
        unboxed_result = emit_unbox!(cg, result, _typeof(cg, args[1]))
        p = alloca!(cg.builder, llvmtype(_typeof(cg, args[1])))
        store!(cg, unboxed_result, p)
        cg.ssas[args[1].id] = p
        return unboxed_result
    end
end

function codegen!(cg::CodeCtx, f::GlobalRef) 
    if haskey(LLVM.functions(cg.mod), string(f.name))
        return LLVM.functions(cg.mod)[string(f.name)]
    end
    evf = eval(f)
    if isa(evf, Type)
        return codegen!(cg, evf)
    else
        # If we refer to something global that we don't have, need to add it as a global variable.
        # return emit_box!(cg, Int32(999)) # KLUDGE - WRONG
        return codegen!(cg, Int32(999)) # KLUDGE - WRONG
    end
end

codegen!(cg::CodeCtx, x::QuoteNode) = codegen!(cg, x.value)
codegen!(cg::CodeCtx, x::Symbol) = emit_symbol!(cg, x)
function codegen!(cg::CodeCtx, x::T) where {T}
    if isbits(T) && sizeof(T) == 0 
        return codegen!(cg, 0)   # I'm not sure how to handle singleton types
    end
    error("Unsupported type: $T")
end

#
# Function calls
#
function codegen!(cg::CodeCtx, ::Val{:call}, args, typ)
    llvmargs = LLVM.Value[]
    llvmargs = Any[]
    fun = eval(args[1])
    name = string(args[1])
    if isa(fun, Core.IntrinsicFunction)
        @debug "$(cg.name): calling intrinsic: $name"
        @info "$(cg.name): calling intrinsic: $name"
        dump(args)
        return emit_intrinsic!(cg, args[1].name, args[2:end])
    end
    if isa(fun, Core.Builtin)
        @debug "$(cg.name): calling builtin: $name"
        return emit_unbox!(cg, emit_builtin!(cg, args[1].name, args[2:end], typ), typ)
    end
    @debug "$(cg.name): calling other method: $name" args
    ## NOTE: everything past here may be wrong!
    argstypetuple = Tuple{(gettypes(cg, a) for a in args[2:end])...}
    @debug "$(cg.name): more info" argstypetuple
    # argstypetuple = Tuple{(Any for a in args[2:end])...}
    global method = which(fun, argstypetuple)
    # codegen!(cg, Val(:invoke), Any[method.specializations.func, args[2:end]...], typ)
    codegen!(cg, Val(:invoke), Any[method, args[2:end]...], typ)
    # error("Function $name not supported.")
end
gettypes(cg::CodeCtx, x::SlotNumber) = cg.code_info.slottypes[x.id]
# gettypes(cg::CodeCtx, x::GlobalRef) = eval(x)
gettypes(cg::CodeCtx, x::GlobalRef) = Type{Any}
gettypes(cg::CodeCtx, x::Expr) = Type{Any}
gettypes(cg::CodeCtx, x) = typeof(x)


function codegen!(cg::CodeCtx, ::Val{:invoke}, args, typ)
    # name = string(Base.function_name(args[1]))
    argtypes = getargtypes(args[1])
    name = getfunname(args[1], argtypes)
    @info "$(cg.name): invoking $name"
    # dump(args, maxdepth=2)
    if haskey(LLVM.functions(cg.mod), name)
        func = LLVM.functions(cg.mod)[name]
    else
        global MI = args[1]
        @debug "$(cg.name): invoke argtypes" args argtypes
        if isa(args[1], Core.MethodInstance)  && isdefined(args[1], :inferred) && args[1].inferred != nothing
            MI = args[1]
            ci = Base.uncompressed_ast(MI.def, MI.inferred)
            dt = MI.rettype
            sig = MI.def.sig
        else
            fun = getfun(args[1])
            methodtable = code_typed(fun, argtypes, optimize = true)
            if length(methodtable) < 1
                @show fun
                @show argtypes
                dump(args, maxdepth=2)
                error("Method not found")
            end
            ci, dt = methodtable[1]
            sig = first(methods(fun, argtypes)).sig
        end
        # @show ci
        # dump(ci, maxdepth=9)
        newcg = CodeCtx(cg, name, ci, dt, argtypes, sig)
        codegen!(newcg)
        func = newcg.func
    end
    llvmargs = LLVM.Value[]
    startpos = isa(args[1], Core.MethodInstance) ? 3 : 2
    for v in args[startpos:end]
        push!(llvmargs, codegen!(cg, v))
    end
    return LLVM.call!(cg.builder, func, llvmargs)
end

# getname(x::Core.MethodInstance) = getfield(x.def.module, x.def.name)
function getname(x::Core.MethodInstance)
    nm = string(getfield(x.def.module, x.def.name))
    if nm != "Type"
        return nm
    end
    return getname(first(x.def.sig.parameters))   
end

function getname(x::Method)
    nm = string(getfield(x.module, x.name))
    if nm != "Type"
        return nm
    end
    first(x.sig.parameters)   
    getname(first(x.sig.parameters))   
    return getname(first(x.sig.parameters))   
end
# getname(x::Method) = getfield(x.module, getname(x.sig.parameters[1]))
getname(::Type{T}) where T = string(T.parameters[1].name.name)
getname(::T) where T = string(T.name.name)
getargtypes(x::Core.MethodInstance) = Tuple{x.specTypes.parameters[2:end]...}
getargtypes(x::Method) = Tuple{x.sig.parameters[2:end]...}
getfun(x::Core.MethodInstance) = getfun(x.def)
getfun(x::Method) = getfield(x.module, basename(x))

function codegen!(cg::CodeCtx, ::Val{:return}, args, typ)
    if length(args) == 1 && args[1] != nothing
        res = codegen!(cg, args[1])
        # @show LLVM.llvmtype(res)
        # @show llvmtype(cg.result_type)
        if LLVM.llvmtype(res) != llvmtype(cg.result_type)
            res = emit_unbox!(cg, res, cg.result_type)
        end
        LLVM.ret!(cg.builder, res)
    else
        LLVM.ret!(cg.builder)
    end
end

#
# Constants / values
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
    return LLVM.call!(cg.builder, cg.extern[:jl_pchar_to_string], LLVM.Value[gs, codegen!(cg, Int32(length(s)+1))])
end

function codegen!(cg::CodeCtx, x::Tuple)
    if isbits(x)
        loc = alloca!(cg.builder, llvmtype(typeof(x)))
        for i in 1:length(x)
            p = LLVM.struct_gep!(cg.builder, loc, i-1)
            store!(cg, codegen!(cg, x[i]), p)
        end
        return LLVM.load!(cg.builder, loc)
    end
end

function codegen!(cg::CodeCtx, x::Array{T,N}) where {T,N}
    # typ = llvmtype(T)
    # array_type = LLVM.call!(cg.builder, cg.extern[:jl_apply_array_type], LLVM.Value[typ, codegen!(cg, UInt32(N))])
    # tuple_type = LLVM.call!(cg.builder, cg.extern[:jl_apply_tuple_type], LLVM.Value[])
    # dims_tuple = jl_new_struct(tuple_type, jl_box...(arg1), jl_box...(arg2), ...);
    # array = LLVM.call!(cg.builder, cg.extern[:jl_new_array], LLVM.Value[array_type, codegen!(cg, UInt32(N))])
    # array = jl_new_array_1d(array_type, length(x))
    # typ = LLVM.load!(cg.builder, cg.datatype[T])
    # return 
end

#
# Miscellaneous
#
codegen!(cg::CodeCtx, ::LineNumberNode) = nothing

codegen!(cg::CodeCtx, ::NewvarNode) = nothing

codegen!(cg::CodeCtx, ::Void) = cg.datatype[Void]

codegen!(cg::CodeCtx, ::Tuple{}) = cg.datatype[Tuple{}]

codegen!(cg::CodeCtx, ::Val{:meta}, args, typ) = nothing

codegen!(cg::CodeCtx, ::Val{:static_parameter}, args, typ) = codegen!(cg, args[1])

codegen!(cg::CodeCtx, ::Val{:simdloop}, args, typ) = nothing
codegen!(cg::CodeCtx, ::Val{:gc_preserve_begin}, args, typ) = codegen!(cg, args[1])


#
# ccall
#
function codegen!(cg::CodeCtx, ::Val{:foreigncall}, args, typ)
    name = isa(args[1], Tuple) ? nameof(args[1][1]) : nameof(args[1])
    if haskey(cg.extern, name)
        @debug "$(cg.name) ccall found: $name"
        func = cg.extern[name]
    else
        @debug "$(cg.name) ccall creating: $name"
        func = extern!(cg.mod, name, llvmtype(args[2]), LLVMType[llvmtype(x) for x in collect(args[3])])
        cg.extern[name] = func
    end
    llvmargs = LLVM.Value[]
    for v in args[6:5+args[5]]
        push!(llvmargs, codegen!(cg, v))
    end
    
    return LLVM.call!(cg.builder, func, llvmargs)
end
nameof(x::QuoteNode) = nameof(x.value)
nameof(x::String) = Symbol(x)
nameof(x) = x

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
    condv = emit_condition!(cg, codegen!(cg, args[1]))
    func = LLVM.parent(LLVM.position(cg.builder))
    ifso = LLVM.BasicBlock(func, "if", ctx)
    ifnot = LLVM.BasicBlock(func, "L", ctx)
    cg.labels[args[2]] = ifnot
    LLVM.br!(cg.builder, condv, ifso, ifnot)
    position!(cg.builder, ifso)
end

emit_condition!(cg, condv) = LLVM.width(LLVM.llvmtype(condv)) > 1 ?
        LLVM.trunc!(cg.builder, condv, int1_t) : condv


#
# New - structure creation
#
function codegen!(cg::CodeCtx, ::Val{:new}, args, typ)
    typ = eval(args[1])
    if isbits(typ)
        @debug "$(cg.name): creating bitstype" args typ llvmtype(typ)
        loc = alloca!(cg.builder, llvmtype(typ))
        for i in 2:length(args)
            p = LLVM.struct_gep!(cg.builder, loc, i-2)
            store!(cg, codegen!(cg, args[i]), p)
        end
        return LLVM.load!(cg.builder, loc)
    else
        dt = load_and_emit_datatype!(cg, args[1])
        @debug "$(cg.name): creating composite" args typ
        llvmargs = LLVM.Value[dt]
        for a in args[2:end]
            push!(llvmargs, emit_box!(cg, a))
        end
        return LLVM.call!(cg.builder, cg.extern[:jl_new_struct], llvmargs)
    end
end


#
# Types - emit and return a stored type or create a new type and store it
#

# The following creates the appropriate structures in memory
function codegen!(cg::CodeCtx, ::Type{Array{T,N}}) where {T,N}
    typ = LLVM.load!(cg.builder, cg.datatype[T])
    return LLVM.call!(cg.builder, cg.extern[:jl_apply_array_type], LLVM.Value[typ, codegen!(cg, UInt32(N))])
end

codegen!(cg::CodeCtx, x::Type{T}) where T = load_and_emit_datatype!(cg, x)


function load_and_emit_datatype!(cg, ::Type{JT}) where JT
    if haskey(cg.datatype, JT)
        return LLVM.load!(cg.builder, cg.datatype[JT])
    end
    name = string(JT)
    @info "$(cg.name): emitting new type: $name"
    typeof(JT) != DataType && error("Not supported, yet")
        # JL_DLLEXPORT jl_value_t *jl_type_union(jl_value_t **ts, size_t n);

    lname = emit_symbol!(cg, JT.name)
    mod = LLVM.load!(cg.builder, cg.extern[:jl_main_module_g])
    super = load_and_emit_datatype!(cg, JT.super)
    params = LLVM.call!(cg.builder, cg.extern[:jl_svec], 
        LLVM.Value[codegen!(cg, length(JT.parameters)), [load_and_emit_datatype!(cg, t) for t in JT.parameters]...])
    if isconcrete(JT)
        fnames = LLVM.call!(cg.builder, cg.extern[:jl_svec], 
            LLVM.Value[codegen!(cg, length(fieldnames(JT))), [emit_symbol!(cg, s) for s in fieldnames(JT)]...])
        ftypes = LLVM.call!(cg.builder, cg.extern[:jl_svec], 
            LLVM.Value[codegen!(cg, length(JT.types)), [load_and_emit_datatype!(cg, t) for t in JT.types]...])
    else
        fnames = ftypes = LLVM.call!(cg.builder, cg.extern[:jl_svec], LLVM.Value[codegen!(cg, 0)])
    end
    abstrct = codegen!(cg, UInt32(JT.abstract))
    mutabl = JT.mutable ? codegen!(cg, UInt32(1)) : codegen!(cg, UInt32(0))
    ninitialized = codegen!(cg, UInt32(JT.ninitialized))
    dt = LLVM.call!(cg.builder, cg.extern[:jl_new_datatype], 
        LLVM.Value[lname, mod, super, params, fnames, ftypes, abstrct, mutabl, ninitialized])
        # LLVMType[jl_sym_t_ptr, jl_module_t_ptr, jl_datatype_t_ptr, jl_svec_t_ptr, jl_svec_t_ptr, jl_svec_t_ptr, int32_t, int32_t, int32_t])
    loc = LLVM.GlobalVariable(cg.mod, jl_datatype_t_ptr, string(JT))
    LLVM.linkage!(loc, LLVM.API.LLVMCommonLinkage)
    # LLVM.initializer!(loc, null(jl_value_t_ptr))
    LLVM.API.LLVMSetInitializer(LLVM.ref(loc), LLVM.ref(null(jl_value_t_ptr)))
    store!(cg, dt, loc)
    result = LLVM.load!(cg.builder, loc)
    cg.datatype[JT] = result
    return result
end

load_and_emit_datatype!(cg, x::GlobalRef) = load_and_emit_datatype!(cg, eval(x))

load_and_emit_datatype!(cg, x) = codegen!(cg, x)

emit_symbol!(cg, x) =
    LLVM.call!(cg.builder, cg.extern[:jl_symbol], [globalstring_ptr!(cg.builder, string(x))])

