# These don't work.

using Test
using CodeGen
using LLVM
using MicroLogging

configure_logging(min_level=:debug)


# Results in several problems below:
codegen(Base.throw_inexacterror, Tuple{Symbol, Type{Int}, Int})
#  Base.throw_inexacterror: invoking Type                                                                       Info main.jl:262
# ERROR: BoundsError: attempt to access 0-element Array{Any,1} at index [1]



codegen(sin, Tuple{Float64})



function test_arrays(x)
    y = fill(2pi, 5)
    push!(y, 3x)
    z = reverse(y)
    zz = y .+ z.^2
    return maximum(zz)
end
codegen(test_arrays, Tuple{Float64})
   

array_max2(x) = maximum([3,x])
codegen(array_max2, Tuple{Int})
codegen(array_max2, Tuple{Float64})


array_sum(x) = sum(Int[3,x])
codegen(array_sum, Tuple{Int}) # same error as above


make_string(x) = string(1, x, "asdf")
codegen(make_string, Tuple{Int}) # same error as above



# Wishful thinking:)
using StaticArrays, OrdinaryDiffEq
function diffeq()
    A  = @SMatrix [ 1.0  0.0 0.0 -5.0
                    4.0 -2.0 4.0 -3.0
                   -4.0  0.0 0.0  1.0
                    5.0 -2.0 2.0  3.0]
    u0 = @SMatrix rand(4,2)
    tspan = (0.0,1.0)
    f(t,u) = A*u
    prob = ODEProblem(f,u0,tspan)
    solve(prob,Tsit5())
    return 1
end
codegen(diffeq)






