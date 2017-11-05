
# NOTE: Tests are broken where commented out.

# For testing: include(Pkg.dir("CodeGen", "test/runtests.jl"))


using Test
using CodeGen
using LLVM
using MicroLogging

configure_logging(min_level=:debug)
configure_logging(min_level=:info)


"""
    @cgtest fun(args...)

Test if `fun(args...)` is equal to `CodeGen.run(fun, args...)`
"""
macro cgtest(e)
    f = e.args[1]
    args = length(e.args) > 1 ? e.args[2:end] : Any[]
    quote
        @test $(esc(e)) == @jitrun($(esc(f)), $(esc.(args)...))
    end
end



array_index(x) = Int[3,2x][2]
@cgtest array_index(2)
println("***")
println(@jlrun(array_index, 2))

array_max(x) = maximum(Int[4,3x])
@test @jitrun(array_max, -1) == array_max(-1)
@cgtest array_max(2)
@cgtest array_max(-1)


function variables(i, j, k) 
    i = 2i + k
    l = j + i
    return l
end
@cgtest variables(3,4,5)
@test variables(3,4,5) == @jitrun(variables,3,4,5)


function variables2(i) 
    x = 5
    y = 9i
    x = x + y
    z = 2x
    return z
end
@cgtest variables2(3)


f() = 99.0
mod = codegen(f, Tuple{})
optimize!(mod)
# @cgtest f()                # both @cgtest and @jitrun are broken with no args
# @test f() == @jitrun(f)


fx(x) = 2x + 50
mod = codegen(fx, Tuple{Int})
optimize!(mod)
@test @jitrun(fx, 10) == fx(10)
# The following is the same test:
@cgtest fx(10)
@cgtest fx(10.0)


z = codegen(abs, Tuple{Float64})
optimize!(z)
verify(z)
@cgtest abs(-10.0)
@cgtest abs(10.0)
@cgtest abs(-10)
@cgtest abs(10)


sum_tuple(x) = sum((x, x, 1.0))
codegen(sum_tuple, Tuple{Float64})
codegen(sum_tuple, Tuple{Float32})
codegen(sum_tuple, Tuple{Int64})
codegen(sum_tuple, Tuple{Int32})
# codegen(sum_tuple, Tuple{Complex128})    # can't box
@cgtest sum_tuple(5)
@cgtest sum_tuple(5.5)


array_max(x) = maximum(Int[3,x])
@cgtest array_max(1)
@cgtest array_max(4)


array_sum(x) = sum(Int[3,x])
m = codegen(array_sum, Tuple{Int})
# verify(m)
@cgtest array_sum(1)


function an_if(x) 
    return x == 3 ? 4 : 5
end
@cgtest an_if(3)
@cgtest an_if(5)


function an_if2(x) 
    if x < 3
        x += 3
    end
    return x+2
end
@cgtest an_if2(5)
@cgtest an_if2(1)


function ifs(x) 
    if x < 7
        if x == 5
            x += 2
        end
        x += 2
    end
    return x+2
end
@cgtest ifs(0)
@cgtest ifs(5)
@cgtest ifs(7)
@cgtest ifs(8)
@cgtest ifs(0.0)
@cgtest ifs(5.0)
@cgtest ifs(7.0)
@cgtest ifs(8.0)


function ifs2(x) 
    if x > 3
        z = 2x
    else
        z = x-4
    end
    return z+2
end
@cgtest ifs2(5)
@cgtest ifs2(3)
@cgtest ifs2(1)


function while_loop(i) 
    x = 5
    while i < 4
        i += 1
        x += 2
    end
    return x
end
@cgtest while_loop(0)


function for_loop(x)
    a = 3
    for i in 1:5
        x += i * a
    end
    x
end
@cgtest for_loop(2)
@cgtest for_loop(2.2)


@noinline f(x) = 2x
function call_another(x)
    y = f(x)
    return x + y
end
@cgtest call_another(3)


function check_identity(x) 
    return x === 3
end
codegen(check_identity, Tuple{Int})


ccall_cos(x) = ccall(:cos, Float64, (Float64,), x)
@cgtest ccall_cos(1.1)


abstract type AbstractMA end
mutable struct MA <: AbstractMA
    xx::Int
    yy::Float64
end
@noinline f(x::MA) = x.yy
function newmdt(x)
    a = MA(1, x)
    f(a)
end
m = codegen(newmdt, Tuple{Float64})
@cgtest newmdt(1.1) 


abstract type AbstractA end
struct A <: AbstractA
    xx::Int
    yy::Float64
end
@noinline f(x::A) = x.yy + x.xx
function newdt(x)
    a = A(3, 2x)
    f(a)
end
@cgtest newdt(1.1) 


@noinline tf(x) = x[2]
function tuple_fun(x)
    t = (x, 2x, 1.0)
    return tf(t)
end
@cgtest tuple_fun(1) 


@noinline tf2(x) = x[1][1] + x[2]
function tuple_fun2(x)
    t = ((x,),3)
    return tf2(t)
end
@cgtest tuple_fun(2)


function test_arrays(x)
    y = fill(2pi, 5)
    push!(y, 3x)
    z = reverse(y)
    zz = y .+ z.^2
    return maximum(zz)
end
@cgtest test_arrays(2.2)


nothing