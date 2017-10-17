
abstract type AbstractCodeCtx end

global ctx = LLVM.Context(convert(LLVM.API.LLVMContextRef, cglobal(:jl_LLVMContext, Void)))

mutable struct CodeCtx <: AbstractCodeCtx
    mod::LLVM.Module
    builder::LLVM.Builder
    code_info::CodeInfo
    result_type::DataType
    name::String
    argtypes
    nargs::Int
    func::LLVM.Function
    current_scope::CurrentScope
    slots::Vector{LLVM.Value}
    ssas::Dict{Int, LLVM.Value}
    meta::Dict{Symbol, Any}
    labels::Dict{Int, Any}
    CodeCtx(ci::CodeInfo, result_type::DataType, name, argtypes) = 
        new(LLVM.Module("JuliaCodeGenModule", ctx),
            LLVM.Builder(ctx),
            ci,
            result_type,
            name,
            argtypes,
            length(argtypes.parameters))
end

# Make a new CodeCtx that shares the same module
function CodeCtx(cg::CodeCtx, code_info, result_type, name, argtypes)
    newcg = CodeCtx(code_info, result_type, name, argtypes)
    newcg.mod = cg.mod
    return newcg
end

llvmtype(x) = LLVMType(ccall(:julia_type_to_llvm, LLVM.API.LLVMTypeRef, (Any, Bool), x, false))

current_scope(cg::CodeGen) = cg.current_scope
function new_scope(f, cg::CodeGen)
    open_scope!(current_scope(cg))
    f()
    pop!(current_scope(cg))
end

function create_entry_block_allocation(cg::CodeGen, fn::LLVM.Function, typ, varname::String)
    local alloc
    LLVM.Builder(cg.ctx) do builder
        # Set the builder at the start of the function
        entry_block = LLVM.entry(fn)
        if isempty(LLVM.instructions(entry_block))
            LLVM.position!(builder, entry_block)
        else
            LLVM.position!(builder, first(LLVM.instructions(entry_block)))
        end
        alloc = LLVM.alloca!(builder, llvmtype(typ), varname)
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
    func_type = LLVM.FunctionType(llvmtype(cg.result_type), argtypes)
    cg.func = LLVM.Function(cg.mod, cg.name, func_type)
    cg.slots = Vector{LLVM.Value}(length(ci.slotnames))
    cg.ssas = Dict{Int, LLVM.Value}()
    cg.labels = Dict{Int, Any}()
    LLVM.linkage!(cg.func, LLVM.API.LLVMExternalLinkage)
    entry = LLVM.BasicBlock(cg.func, "entry", ctx)
    LLVM.position!(cg.builder, entry)
    for (i, slottype) in enumerate(ci.slottypes[2:end])
        varname = string(ci.slotnames[i])
        alloc = LLVM.alloca!(builder, llvmtype(slottype), varname)
        LLVM.store!(cg.builder, slottype, alloc)
        current_scope(cg)[varname] = alloc
        # LLVM.name!(param, varname)
    end
    for node in ci.code
        codegen!(cg, node)
    end
    # LLVM.verify(func)
    # LLVM.dispose(cg.builder)  # ?? something different for multiple funs 
    return cg.mod
end

Base.show(io::IO, cg::CodeCtx) = print(io, "CodeCtx")

function codegen!(cg::CodeCtx, e::Expr)
    # Slow dispatches here but easy to write and to customize
    codegen!(cg, Val(e.head), e.args) 
end

function codegen!(cg::CodeCtx, ::LineNumberNode)
end

#
# Function calls
#
function codegen!(cg::CodeCtx, ::Val{:call}, args)
    llvmargs = LLVM.Value[]
    llvmargs = Any[]
    for v in args[2:end]
        push!(llvmargs, codegen!(cg, v))
    end
    
    fun = eval(args[1])
    if isa(fun, Core.IntrinsicFunction)
        return emit_intrinsic!(cg, args[1].name, llvmargs)
    end
end

function codegen!(cg::CodeCtx, ::Val{:invoke}, args)
    llvmargs = LLVM.Value[]
    for v in args[3:end]
        push!(llvmargs, codegen!(cg, v))
    end
    # name = string(Base.function_name(args[1]))
    name = string(args[2])
    @show name
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

    return LLVM.call!(cg.builder, func, llvmargs)
end

function codegen!(cg::CodeCtx, ::Val{:meta}, args)
end

function codegen!(cg::CodeCtx, ::Val{:return}, args)
    if length(args) == 1
        LLVM.ret!(cg.builder, codegen!(cg, args[1]))
    else
        LLVM.ret!(cg.builder)
    end
end

#
# Variable assignment and reading
#
function codegen!(cg::CodeCtx, v::SlotNumber) 
    cg.slots[v.id]
    V = get(current_scope(cg), varname, nothing)
    V == nothing && error("did not find variable $(varname)")
    return LLVM.load!(cg.builder, V, expr.name)
end

function codegen!(cg::CodeCtx, ::Val{:(=)}, args)
    result = codegen!(cg, args[2])
    if isa(args[1], SlotNumber)
        varname = string(cg.code_info.slotnames[args[1].id])
        V = get(current_scope(cg), varname, nothing)
        V == nothing && error("unknown variable name $(varname)")
        LLVM.store!(cg.builder, result, V)
        LLVM.name!(result, varname)
        cg.slots[args[1].id] = result
        return result
    end
    if isa(args[1], SSAValue)
        cg.ssas[args[1].id] = result
        return result
    end
end


#
# Constants and types
#
codegen!(cg::CodeCtx, x::T) where T <: Base.IEEEFloat =
    LLVM.ConstantFP(llvmtype(T), x)

codegen!(cg::CodeCtx, x::T) where T <: Base.BitInteger =
    LLVM.ConstantInt(llvmtype(T), x)

codegen!(cg::CodeCtx, ::Type{T}) where T <: Base.IEEEFloat =
    llvmtype(T)

codegen!(cg::CodeCtx, ::Type{T}) where T <: Base.BitInteger =
    llvmtype(T)

codegen!(cg::CodeCtx, x::T) where T = llvmtype(T)


codegen!(cg::CodeCtx, v::SSAValue) = cg.ssas[v.id]


#
# ccall
#
function codegen!(cg::CodeCtx, ::Val{:foreigncall}, args)

    llvmargs = LLVM.Value[]
    for v in args[6:end]
        push!(llvmargs, codegen!(cg, v))
    end
    
    func_type = LLVM.FunctionType(llvmtype(cg.result_type), LLVMType[llvmtype(p) for p in cg.argtypes.parameters])
    func = LLVM.Function(cg.mod, cg.name, func_type)
    LLVM.linkage!(func, LLVM.API.LLVMExternalLinkage)

    return LLVM.call!(cg.builder, func, llvmargs)
end

#
# Control
#
function codegen!(cg::CodeCtx, ln::LabelNode)
    if !haskey(cg.labels, ln.label)
        func = LLVM.parent(LLVM.position(cg.builder))
        cg.labels[ln.label] = LLVM.BasicBlock(func, "label", ctx)
    end
    # br!(cg.builder, cg.labels[ln.label])
    position!(cg.builder, cg.labels[ln.label])
end

function codegen!(cg::CodeCtx, gn::GotoNode)
    if !haskey(cg.labels, gn.label)
        func = LLVM.parent(LLVM.position(cg.builder))
        cg.labels[gn.label] = LLVM.BasicBlock(func, "label", ctx)
    end
    br!(cg.builder, cg.labels[gn.label])
end

function codegen!(cg::CodeCtx, ::Val{:gotoifnot}, args)
    condv = codegen!(cg, args[1])
    func = LLVM.parent(LLVM.position(cg.builder))
    ifso = LLVM.BasicBlock(func, "if", ctx)
    ifnot = LLVM.BasicBlock(func, "else", ctx)
    cg.labels[args[2]] = ifnot
    LLVM.br!(cg.builder, condv, ifso, ifnot)
    position!(cg.builder, ifso)
end

#         LLVM.br!(cg.builder, condv, then, elsee)


# function codegen!(cg::CodeCtx, expr::IfExprAST)
#     func = LLVM.parent(LLVM.position(cg.builder))
#     then = LLVM.BasicBlock(func, "then", cg.ctx)
#     elsee = LLVM.BasicBlock(func, "else", cg.ctx)
#     merge = LLVM.BasicBlock(func, "ifcont", cg.ctx)

#     local phi
#     new_scope(cg) do
#         # if
#         cond = codegen!(cg, expr.cond)
#         zero = LLVM.ConstantFP(LLVM.DoubleType(cg.ctx), 0.0)
#         condv = LLVM.fcmp!(cg.builder, LLVM.API.LLVMRealONE, cond, zero, "ifcond")
#         LLVM.br!(cg.builder, condv, then, elsee)

#         # then
#         LLVM.position!(cg.builder, then)
#         thencg = codegen!(cg, expr.then)
#         LLVM.br!(cg.builder, merge)
#         then_block = position(cg.builder)

#         # else
#         LLVM.position!(cg.builder, elsee)
#         elsecg = codegen!(cg, expr.elsee)
#         LLVM.br!(cg.builder, merge)
#         else_block = position(cg.builder)

#         # merge
#         LLVM.position!(cg.builder, merge)
#         phi = LLVM.phi!(cg.builder, LLVM.DoubleType(cg.ctx), "iftmp")
#         append!(LLVM.incoming(phi), [(thencg, then_block), (elsecg, else_block)])
#     end

#     return phi
# end

# function codegen!(cg::CodeCtx, expr::ForExprAST)
#     new_scope(cg) do
#         # Allocate loop variable
#         startblock = position(cg.builder)
#         func = LLVM.parent(startblock)
#         alloc = create_entry_block_allocation(cg, func, expr.varname)
#         current_scope(cg)[expr.varname] = alloc
#         start = codegen!(cg, expr.start)
#         LLVM.store!(cg.builder, start, alloc)

#         # Loop block
#         loopblock = LLVM.BasicBlock(func, "loop", cg.ctx)
#         LLVM.br!(cg.builder, loopblock)
#         LLVM.position!(cg.builder, loopblock)

#         # Code for loop block
#         codegen!(cg, expr.body)
#         step = codegen!(cg, expr.step)
#         endd = codegen!(cg, expr.endd)

#         curvar = LLVM.load!(cg.builder, alloc, expr.varname)
#         nextvar = LLVM.fadd!(cg.builder, curvar, step, "nextvar")
#         LLVM.store!(cg.builder, nextvar, alloc)

#         endd = LLVM.fcmp!(cg.builder, LLVM.API.LLVMRealONE, endd,
#             LLVM.ConstantFP(LLVM.DoubleType(cg.ctx), 0.0))

#         loopendblock = position(cg.builder)
#         afterblock = LLVM.BasicBlock(func, "afterloop", cg.ctx)

#         LLVM.br!(cg.builder, endd, loopblock, afterblock)
#         LLVM.position!(cg.builder, afterblock)
#     end

#     # loops return 0.0 for now
#     return LLVM.ConstantFP(LLVM.DoubleType(cg.ctx), 0.0)
# e