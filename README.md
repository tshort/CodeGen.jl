# CodeGen

**This package is a work in progress.**

The main purpose of this package is to generate LLVM IR from Julia code. It is targeted (for now) at static code.

Example:

```julia
myfun(x) = sum((x, x, 1.0))

codegen(myfun, Tuple{Float64})
```

This package uses the awesome [LLVM.jl package](https://github.com/maleadt/LLVM.jl). LLVM.jl requires special installation instructions--it requires a source build of Julia (see their site for more info).

