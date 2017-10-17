
module CodeGen

export codegen!, codegen

using LLVM

include("main.jl")
include("intrinsics.jl")

end # module
