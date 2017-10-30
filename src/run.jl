#
# Bitcode optimization and running utilities.
# 

export optimize!, @jitrun, @jlrun

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

macro jitrun(fun, args...)
    innerfun = gensym(fun)
    quote
        $innerfun() = $(esc(fun))($(esc(args...)))
        _jitrun($innerfun)
    end
end
function _jitrun(fun)
    # LLVM.@apicall(:LLVMLinkInJIT,LLVM.API.LLVMBool,())
    LLVM.API.LLVMInitializeNativeTarget()
    mod = codegen(fun, Tuple{})
    optimize!(mod)
    ci = code_typed(fun, Tuple{})
    restype = last(last(ci))
    funname = string(first(methods(fun)).name)
    res_jl = 0
    LLVM.JIT(mod) do engine
        # LLVM.JIT() won't work with arbitrary inputs.
        # See https://github.com/maleadt/LLVM.jl/issues/21
        if !haskey(LLVM.functions(engine), funname)
            error("did not find $funname function in module")
        end
        f = LLVM.functions(engine)[funname]
        res = LLVM.run(engine, f)
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

export @jlrun
macro jlrun(fun, args...)
    CodeGen._jlrun(fun, args...)
end
function _jlrun(fun, args...)
    quote
        efun = $(esc(fun))
        eargs = $(esc(args))
        tt = Tuple{(typeof(a) for a in eargs)...}
        mod = codegen(efun, tt)
        optimize!(mod)
        ci = code_typed(efun, tt)
        restype = last(last(ci))
        funname = string(efun)
        innerfun() = Base.llvmcall(LLVM.ref(functions(mod)[funname]), restype, tt, $(esc(args...)))
        innerfun()
    end
end


function Base.write(mod::LLVM.Module, path::String)
    open(io -> write(io, mod), path, "w")
end

# Base.write(cg::CodeGen, path::String) = write(cg.mod, path)

