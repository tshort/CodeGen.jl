# CodeGen

**This package is experimental and a work in progress.**

The main purpose of this package is to generate LLVM IR from Julia code. It is targeted (for now) at static code. The resulting IR can be save to a bitcode (.bc) file that can be compiled with Clang. It requires Julia dev-0.7.

Example:

```julia
myfun(x) = sum((x, x, 1.0))

llvm_module = codegen(myfun, Tuple{Float64})
write(llvm_module, "myfun.bc")
```

For some code, you can also test it in Julia. It generates code but uses LLVM's JIT compiler to compile and run it. Here is an example:

```julia
@jitrun(myfun, 2.3) == myfun(2.3)
```

This package uses the awesome [LLVM.jl package](https://github.com/maleadt/LLVM.jl). LLVM.jl requires special installation instructions--it requires a source build of Julia (see their site for more info).

The approach here is much simpler than the codegen in base Julia. Here, the main language constructs and intrinsics are converted to LLVM IR. Generic functions and other constructs are coded using the C API.