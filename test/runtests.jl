
# NOTE: Tests are broken where `verify` is commented out.

using Test
using CodeGen
using LLVM

abs_fun(x) = abs(x)

verify(codegen(abs_fun, Tuple{Float64}))
z = codegen(abs_fun, Tuple{Float64})
optimize!(z)
# @show z


array_max(x) = maximum(Int[3,x])

# @show code_typed(Base._mapreduce, Tuple{typeof(identity), typeof(Base.scalarmax), IndexLinear, Array{Int32,1}}, optimize=true)
# @show code_typed(Base._mapreduce, Tuple{typeof(identity), typeof(Base.scalarmax), IndexLinear, Array{Int32,1}}, optimize=false)

# This one works with `include(Pkg.dir("CodeGen", "test/runtests.jl")` but not with `Pkg.test("CodeGen")`.
# At the REPL, a `Base.OneTo` gets optimized out, but it doesn't in the test version.
verify(codegen(array_max, Tuple{Int}))

sum_tuple(x) = abs(sum((x, x, 1.0)))

verify(codegen(sum_tuple, Tuple{Float64}))
verify(codegen(sum_tuple, Tuple{Float32}))
verify(codegen(sum_tuple, Tuple{Int64}))
verify(codegen(sum_tuple, Tuple{Int32}))
# verify(codegen(sum_tuple, Tuple{Complex128}))

function for_loop(x)
    a = 3
    for i in 1:5
        x += i * a
    end
    x
end

verify(codegen(for_loop, Tuple{Int}))
# verify(codegen(for_loop, Tuple{Float64}))

@noinline f(x) = 2x
function call_another(x)
    y = f(x)
    return x + y
end

verify(codegen(call_another, Tuple{Int}))

function ifs(x) 
    if x > 3
        if x > 5
            x += 2
        end
        x += 2
    end
    return x+2
end

verify(codegen(ifs, Tuple{Int}))

function ifs2(x) 
    if x > 3
        z = 2x
    else
        z = x-4
    end
    return z+2
end

verify(codegen(ifs2, Tuple{Int}))

function while_loop(x) 
    i = 1
    while i < 4
        i += 1
        x += 2
    end
    return x
end

verify(codegen(while_loop, Tuple{Int}))

function check_identity(x) 
    return x === 3
end

# verify(codegen(check_identity, Tuple{Int}))

function another_if(x) 
    return x == 3 ? 4 : 5
end

verify(codegen(another_if, Tuple{Int}))

function do_ccall(x) 
    return ccall(:myccall, Int, (Int,), 1)
end

verify(codegen(do_ccall, Tuple{Int}))

make_string(x) = string(1, x, "asdf")

# verify(codegen(make_string, Tuple{Int}))

function array_max2(x) 
    return maximum([3,x])
end

# verify(codegen(array_max2, Tuple{Int}))
# verify(codegen(array_max2, Tuple{Float64}))

z = codegen(while_loop, Tuple{Int})
optimize!(z)
write(z, "ex.bc")




