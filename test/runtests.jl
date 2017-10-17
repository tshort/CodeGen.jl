
using Base.Test
using CodeGen

myfun(x) = sum((x, x, 1.0))

codegen(myfun, Tuple{Float64})
