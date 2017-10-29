#
# Bitcode optimization and running utilities.
# 

export optimize!, run

"""
    optimize!(mod::LLVM.Module)

Optimize the LLVM module `mod`. Crude for now. 
Returns nothing.
"""
function optimize!(mod::LLVM.Module)
    tm = TargetMachine(Target("i686-pc-linux-gnu"), "i686-pc-linux-gnu")
    LLVM.ModulePassManager() do pm
        global_optimizer!(pm)
        global_dce!(pm)
        strip_dead_prototypes!(pm)
        add_transform_info!(pm, tm)
        # ccall(:LLVMAddLowerGCFramePass, Void,
        #       (LLVM.API.LLVMPassManagerRef,), LLVM.ref(pm))
        # ccall(:LLVMAddLowerPTLSPass, Void,
        #       (LLVM.API.LLVMPassManagerRef, Cint), LLVM.ref(pm), 1)
        PassManagerBuilder() do pmb
            always_inliner!(pm)
            populate!(pm, pmb)
        end
        LLVM.run!(pm, mod)
    end
    return nothing
end

function run(fun, args...)
    # LLVM.@apicall(:LLVMLinkInJIT,LLVM.API.LLVMBool,())
    LLVM.API.LLVMInitializeNativeTarget()
    tt = Tuple{(typeof(a) for a in args)...}
    mod = codegen(fun, tt)
    optimize!(mod)
    ci = code_typed(fun, tt)
    restype = last(last(ci))
    funname = string(fun)
    res_jl = 0
    # LLVM.Interpreter(mod) do engine
    # LLVM.JIT(mod) do engine    # This gives wrong answers with JIT and with ExecutionEngine
    LLVM.ExecutionEngine(mod) do engine
        if !haskey(LLVM.functions(engine), funname)
            error("did not find $funname function in module")
        end
        f = LLVM.functions(engine)[funname]
        llvmargs = [LLVM.GenericValue(llvmtype(typeof(a)), a) for a in args]
        if length(args) > 0
            res = LLVM.run(engine, f, llvmargs)
        else
            res = LLVM.run(engine, f)
        end
        if restype <: Integer
            res_jl = convert(restype, res)
        elseif restype <: AbstractFloat
            res_jl = convert(restype, res, llvmtype(restype))
        else
            res_jl = convert(restype, res)
        end
        LLVM.dispose(res)
    end
    return res_jl
end



function Base.write(mod::LLVM.Module, path::String)
    open(io -> write(io, mod), path, "w")
end

# Base.write(cg::CodeGen, path::String) = write(cg.mod, path)

