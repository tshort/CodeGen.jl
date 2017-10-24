#
# Bitcode optimization and running utilities.
# 

export optimize!

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

#
# BROKEN
#
function LLVM.run(mod::LLVM.Module, fun::String, restype, args...)
    res_jl = 0.0
    LLVM.JIT(mod) do engine
        if !haskey(LLVM.functions(engine), fun)
            error("did not find $fun function in module")
        end
        f = LLVM.functions(engine)[fun]
        global llvmargs = [LLVM.GenericValue(llvmtype(typeof(a)), a) for a in args]
        global res = LLVM.run(engine, f, llvmargs)
        res_jl = convert(restype, res)
        # LLVM.dispose(res)
    end
    return res_jl
end


function Base.write(mod::LLVM.Module, path::String)
    open(io -> write(io, mod), path, "w")
end

# Base.write(cg::CodeGen, path::String) = write(cg.mod, path)

