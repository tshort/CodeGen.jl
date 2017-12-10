
abstract type AbstractCodeCtx end

"""
The `CodeCtx` type holds the main state for code generation. 
One instance is used per function being compiled.
"""
mutable struct CodeCtx <: AbstractCodeCtx
    builder::LLVM.Builder
    mod::LLVM.Module
    name::String
    code_info::CodeInfo
    result_type
    argtypes
    sig
    nargs::Int
    slots::Vector{LLVM.Value}
    slotlocs::Vector{Any}
    ssas::Dict{Int, LLVM.Value}
    labels::Dict{Int, Any}
    meta::Dict{Symbol, Any}
    func::LLVM.Function
    extern::Dict{Symbol, Any}
    builtin::Dict{Symbol, LLVM.Function}
    datatype::Dict{Type, Any}
    CodeCtx(mod::LLVM.Module, name, ci::CodeInfo, result_type, argtypes, sig) = 
        new(LLVM.Builder(ctx),
            mod, 
            name,
            ci,
            result_type,
            argtypes,
            sig,
            length(argtypes.parameters),
            Vector{LLVM.Value}(uninitialized, length(ci.slotnames)),
            Vector{Any}(uninitialized, length(ci.slotnames)),
            Dict{Int, LLVM.Value}(),
            Dict{Int, Any}(),
            Dict{Symbol, Any}()
            )
end

function CodeCtx(name, ci::CodeInfo, result_type, argtypes, sig; triple = nothing, datalayout = nothing)
    cg = CodeCtx(LLVM.Module("JuliaCodeGenModule", ctx), name, ci, result_type, argtypes, sig)
    global CG = cg
    M = cg.mod
    triple != nothing && triple!(cg.mod, triple)
    datalayout != nothing && datalayout!(cg.mod, datalayout)
    cg.builtin = setup_builtins!(cg)
    cg.extern = setup_externs!(cg.mod)
    cg.datatype = setup_types!(cg)
    return cg
end

CodeCtx(; triple = nothing, datalayout = nothing) = 
    cg = CodeCtx(LLVM.Module("JuliaCodeGenModule", ctx), "", CodeInfo(), Void, Tuple{}, Tuple{}, triple = triple, datalayout = datalayout)


function CodeCtx(orig_cg::CodeCtx, name, ci::CodeInfo, result_type, argtypes, sig)
    cg = CodeCtx(orig_cg.mod, name, ci, result_type, argtypes, sig)
    cg.builtin = orig_cg.builtin
    cg.extern = orig_cg.extern
    cg.datatype = orig_cg.datatype
    return cg
end

function CodeCtx(@nospecialize(fun), @nospecialize(argtypes); optimize_lowering = true, triple = nothing, datalayout = nothing)
    ci, dt = code_typed(fun, argtypes, optimize = optimize_lowering)[1]
    @show ci
    sig = first(methods(fun, argtypes)).sig
    funname = string(Base.function_name(fun))
    cg = CodeCtx(funname, ci, dt, argtypes)
    codegen!(cg)
    return cg
end

# This is for testing
function CodeCtx_init(@nospecialize(fun), @nospecialize(argtypes); optimize_lowering = true, triple = nothing, datalayout = nothing)
    ci, dt = code_typed(fun, argtypes, optimize = optimize_lowering)[1]
    @show ci
    sig = first(methods(fun, argtypes)).sig
    funname = string(Base.function_name(fun))
    cg = CodeCtx(funname, ci, dt, argtypes, sig)
    @info "## $(cg.name)"
    ci = cg.code_info
    argtypes = LLVMType[llvmtype(p) for p in cg.argtypes.parameters]
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
    return cg
end

Base.show(io::IO, cg::CodeCtx) = print(io, "CodeCtx")
