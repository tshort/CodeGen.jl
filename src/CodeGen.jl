
module CodeGen

export codegen, codegen!

using LLVM

include("init.jl")
include("scope.jl")
include("main.jl")
include("intrinsics.jl")
include("builtins.jl")
include("run.jl")

end # module
