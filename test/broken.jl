# These don't work.

using Test
using CodeGen
using LLVM
using MicroLogging

configure_logging(min_level=:info)
configure_logging(min_level=:debug)



# # Results in several problems below:  codegen of this works now
# codegen(Base.throw_inexacterror, Tuple{Symbol, Type{Int}, Int})


# abstract type AbstractA end
# struct A <: AbstractA
#     xx::Int
#     yy::Float64
# end
# testf() = 99

# cg = CodeGen.CodeCtx_init(testf, Tuple{})
# addr = LLVM.alloca!(cg.builder, CodeGen.llvmtype(A))
# gaddr = LLVM.struct_gep!(cg.builder, addr, 0)
# LLVM.store!(cg.builder, codegen!(cg, 3), gaddr)
# gaddr2 = LLVM.struct_gep!(cg.builder, addr, 1)
# LLVM.store!(cg.builder, codegen!(cg, 2.2), gaddr2)
# v = LLVM.load!(cg.builder, gaddr)
# LLVM.ret!(cg.builder, v)
# verify(cg.mod)





function test_arrays(x)
    y = fill(2pi, 5)
    # z = fill(x, 5)
    z = 2y .+ y  # works
    # z = 2y # works
    # zz = 2 .+ y  # segfaults
    return z[1]
end
m = codegen(test_arrays, Tuple{Float64})
verify(m)
# @jitrun(test_arrays, 1.1) 
# nothing
# # print(m)

# @jlrun(test_arrays, 1.1) 



# array_max2(x) = maximum([3,x])
# codegen(array_max2, Tuple{Int})     # This passes & verifies
# # @cgtest array_max2(1)               # Segfaults...
# codegen(array_max2, Tuple{Float64}) # no method matching emit_box!(::CodeGen.CodeCtx, ::Type{Tuple{Int64,Float64}}, ::LLVM.LoadInst)  


# function test_arrays(x)
#     y = fill(2pi, 5)
#     push!(y, 3x)
#     z = reverse(y)
#     zz = y .+ z.^2
#     return maximum(zz)
# end
# codegen(test_arrays, Tuple{Float64})  
   

# make_string(x) = string(1, x, "asdf")
# codegen(make_string, Tuple{Int}) # same error as above


# codegen(sin, Tuple{Float64})


# function type_unstable(x)
#     for i = 1:10
#       x = x/2
#     end
#     return x
# end
# codegen(type_unstable, Tuple{Int})
# # @jitrun(type_unstable, 1)   # segfaults



# # Wishful thinking:)
# using StaticArrays, OrdinaryDiffEq
# function diffeq()
#     A  = @SMatrix [ 1.0  0.0 0.0 -5.0
#                     4.0 -2.0 4.0 -3.0
#                    -4.0  0.0 0.0  1.0
#                     5.0 -2.0 2.0  3.0]
#     u0 = @SMatrix rand(4,2)
#     tspan = (0.0,1.0)
#     f(t,u) = A*u
#     prob = ODEProblem(f,u0,tspan)
#     solve(prob,Tsit5())
#     return 1
# end
# codegen(diffeq)

