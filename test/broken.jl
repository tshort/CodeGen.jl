# These don't work.


codegen(sin, Tuple{Float64})


array_max2(x) = maximum([3,x])
codegen(array_max2, Tuple{Int})
#  Base.throw_inexacterror: invoking Type                                                                       Info main.jl:262
# ERROR: BoundsError: attempt to access 0-element Array{Any,1} at index [1]
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






