
module CodeGen

export codegen!, codegen

using LLVM

include("init.jl")
include("scope.jl")
include("mainnew.jl")
include("intrinsics.jl")
include("builtins.jl")

end # module
