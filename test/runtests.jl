
# NOTE: Tests are broken where commented out.

# For testing: include(Pkg.dir("CodeGen", "test/runtests.jl"))


using Test
using CodeGen
using LLVM

Base.CoreLogging.global_logger(Base.CoreLogging.SimpleLogger(stderr))
# Base.CoreLogging.global_logger(Base.CoreLogging.SimpleLogger(stderr, Base.CoreLogging.Debug))


"""
    @cgtest fun(args...)

Test if `fun(args...)` is equal to `CodeGen.run(fun, args...)`
"""
macro cgtest(e)
    f = e.args[1]
    @show args = length(e.args) > 1 ? e.args[2:end] : Any[]
    esc(quote
        # @test $(e) == @jitrun($(f), $(args...))
        $(e) == @jitrun($f, $(args...))
    end)
end


f(x) = 3
m = codegen(f, Tuple{Int})
@cgtest f(2)


array_max(x) = maximum(Int[4,3x])
# m = codegen(array_max, Tuple{Int})
# verify(m)
# @test @jitrun(array_max, -1) == array_max(-1)
# @cgtest array_max(2)
# @cgtest array_max(-1)


function variables(i, j, k) 
    i = 2i + k
    l = j + i
    return l
end
@cgtest variables(3,4,5)
# @test variables(3,4,5) == @jitrun(variables,3,4,5)


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
@cgtest fx(10)
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
# @cgtest array_max(1)
# @cgtest array_max(4)


array_sum(x) = sum(Int[3,x])
# m = codegen(array_sum, Tuple{Int})
# verify(m)
# @cgtest array_sum(1)


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


function array_len(x)
    a = Int[3,4,5]
    return length(a)
end
@cgtest array_len(2)


rfib(n) = n < 2 ? n : rfib(n-1) + rfib(n-2)
@cgtest rfib(9)


@noinline mdisp(x) = 4x
@noinline mdisp(x,y) = x + y
test_dispatch(x,y) = mdisp(x, y) + mdisp(x) + mdisp(y)
@cgtest test_dispatch(1,2)
@cgtest test_dispatch(1,2.0)


@cgtest Base.shl_int(4096,2)
@cgtest Base.shl_int(UInt(4096),2)
@cgtest Base.shl_int(UInt16(4096),2)
@cgtest Base.shl_int(4096,UInt8(2))
@cgtest Base.lshr_int(4096,2)
@cgtest Base.lshr_int(UInt(4096),2)
@cgtest Base.lshr_int(UInt16(4096),2)
@cgtest Base.lshr_int(4096,UInt8(2))
@cgtest Base.ashr_int(4096,2)
@cgtest Base.ashr_int(UInt(4096),2)
@cgtest Base.ashr_int(UInt16(4096),2)
@cgtest Base.ashr_int(4096,UInt8(2))



mutable struct X
    x::Int
end
@noinline f(x) = X(x)
g(x) = f(x).x + x
m = codegen(g, Tuple{Int})
# verify(m)
@cgtest g(2)

function varargs_fun(x, y::Int...)
    a = y[1]
    b = 3
    return x + a + b
end
@cgtest varargs_fun(2, 3)
@cgtest varargs_fun(2, 3, 4)

nothing