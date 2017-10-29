
# NOTE: Tests are broken where commented out.

# For testing: include(Pkg.dir("CodeGen", "test/runtests.jl"))


using Test
using CodeGen
using LLVM
using MicroLogging

configure_logging(min_level=:debug)


"""
    @cgtest fun(args...)

Test if `fun(args...)` is equal to `CodeGen.run(fun, args...)`
"""
macro cgtest(e)
    esc(_cgtest(e))
end
function _cgtest(e)
    f = e.args[1]
    args = length(e.args) > 1 ? e.args[2:end] : Any[]
    quote
        println($(string(e)))
        @test $e == CodeGen.run($f, $(args...))
    end
end


function variables(i) 
    i = 2i
    return i
end
# @cgtest variables(UInt32(3))  # ERROR: MethodError: no method matching codegen!(::CodeGen.CodeCtx, ::TypedSlot)
# @cgtest variables(UInt64(3))
@cgtest variables(3)
@cgtest variables(3.3)
@cgtest variables(Float32(3.3))


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
# @show CodeGen.run(f)     # Not sure why this doesn't work


fx(x) = 2x + 50
mod = codegen(fx, Tuple{Int})
optimize!(mod)
@test CodeGen.run(fx, 10) == fx(10)
# The following is the same test:
@cgtest fx(10)
@cgtest fx(10.0)


abs_fun(x) = abs(x)

z = codegen(abs_fun, Tuple{Float64})
optimize!(z)
verify(z)
# @cgtest abs_fun(-10.0)   #  unknown external function: llvm.fabs
# @cgtest abs_fun(10.0)
# @cgtest abs_fun(-10)


array_max(x) = maximum(Int[3,x])
codegen(array_max, Tuple{Int})


sum_tuple(x) = sum((x, x, 1.0))
codegen(sum_tuple, Tuple{Float64})
codegen(sum_tuple, Tuple{Float32})
codegen(sum_tuple, Tuple{Int64})
codegen(sum_tuple, Tuple{Int32})
codegen(sum_tuple, Tuple{Complex128})
@cgtest sum_tuple(5)
@cgtest sum_tuple(5.5)


function type_unstable()
    x=1
    for i = 1:10
      x = x/2
    end
    return x
end
codegen(type_unstable, Tuple{})


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


function do_ccall(x) 
    return ccall(:myccall, Int, (Int,), 1)
end
codegen(do_ccall, Tuple{Int})


nothing