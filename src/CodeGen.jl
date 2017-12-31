
module CodeGen

export codegen, codegen!
export optimize!, @jitrun, @jlrun


using LLVM

include("types.jl")        # CodeCtx
include("codegens.jl")
include("init.jl")
include("boxing.jl")
include("intrinsics.jl")
include("builtins.jl")
include("run.jl")
include("misc.jl")

end # module
