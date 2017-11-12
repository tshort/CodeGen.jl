# These don't work.

using Test
using CodeGen
using LLVM
using MicroLogging

configure_logging(min_level=:info)
configure_logging(min_level=:debug)



# @cgtest sqrt(2.0)    # intrinsic issue with add_ptr


# @noinline mdisp(x) = 4x
# @noinline mdisp(x,y) = x + y
# test_dispatch(x) = mdisp(x) + mdisp(x, 2x)
# m = codegen(test_dispatch, Tuple{Int})  # codegens, but doesn't make multiple versions of mdisp



# m = codegen(Base.Math.rem_pio2_kernel, Tuple{Float64})
# @jitrun(Base.Math.rem_pio2_kernel, 1.1)
# nothing




# function varargs_fun(y::Int...)
#     a = y[1]
#     b = 3
#     return a + b
# end
# ci = code_typed(varargs_fun, Tuple{Int, Int})
# m = first(methods(varargs_fun, Tuple{Int, Int}))
# m = codegen(varargs_fun, Tuple{Int, Int})   # segfaults


# ci = code_typed(string, Tuple{String, String})
# mt = first(methods(string, Tuple{String, String}))
# m = codegen(string, Tuple{String, String})
# nothing
# m = codegen(Base.print_to_string, Tuple{Float64})
# m = codegen(sin_fast, Tuple{Float64}) # tries to call libopenlibm
# m = codegen(rand, Tuple{}) #  ccall issue
# m = codegen(sin, Tuple{Float64}) # compiles; verification fails big-time


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






# array_max2(x) = maximum([3,x])
# m = codegen(array_max2, Tuple{Int})   # This runs; several verification problems
# # @cgtest array_max2(1)               # Segfaults...
# codegen(array_max2, Tuple{Float64})
# @jitrun(array_max2, 1.1)          


   

# make_string(x) = string(1, x, "asdf")
# m = codegen(make_string, Tuple{Int}) # Unsupported intrinsic: arraylen



# function type_unstable(x)
#     for i = 1:10
#       x = x/2
#     end
#     return x
# end
# m = codegen(type_unstable, Tuple{Int})
# verify(m)
# nothing
# @jitrun(type_unstable, 1)   # segfaults



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

