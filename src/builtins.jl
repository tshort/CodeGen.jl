function emit_box!(cg::CodeCtx, v, t::LLVM.IntegerType)
    t == jl_value_t_ptr && return v
    t == int64_t && return LLVM.call!(cg.builder, cg.extern[:jl_box_int64_f], LLVM.Value[v])
    t == int8_t  && return LLVM.call!(cg.builder, cg.extern[:jl_box_int8_f], LLVM.Value[v])
    error("Boxing of $t not supported")
end
emit_box!(cg::CodeCtx, v, t::LLVM.PointerType) = v

function emit_unbox!(cg::CodeCtx, v, ::Type{T}) where T
    t = LLVM.llvmtype(v) 
    t == int64_t && return v
    t == int8_t && return v
    if t == jl_value_t_ptr 
        T == Int64 && return LLVM.call!(cg.builder, cg.extern[:jl_unbox_int64_f], LLVM.Value[v])
    end
    error("Unboxing of $t not supported")
end


function emit_builtin!(cg::CodeCtx, name, args)
    nargs = length(args)
    if name == :(===) && nargs == 2
        # if isbits(args[1]) && typeof(args[1]) == typeof(args[2])
            # if isa(args[1], Integer)
                # Need to box result?
                return emit_intrinsic!(cg, :eq_int, args)
            # end
        # end
    end 
    @show name nargs
    # Otherwise default to the C++ versions of these.
    # BROKEN
    # need to create an array in llvm
    cgnargs = codegen!(cg, UInt32(nargs))
    newargs = LLVM.array_alloca!(cg.builder, jl_value_t_ptr, cgnargs)
    for i in 1:nargs
        @show i, args[i]
        @show LLVM.llvmtype(args[i])
        v = emit_box!(cg, args[i], LLVM.llvmtype(args[i]))
        p = LLVM.gep!(cg.builder, newargs, [codegen!(cg, i-1)])
        LLVM.store!(cg.builder, v, p)
    end
    println("Almost done")
    func = cg.builtin[name]
    x = codegen!(cg, 0)
    dumfunc = emit_box!(cg, x, LLVM.llvmtype(x)) ## Dummy to see if this gets stuff working
    return LLVM.call!(cg.builder, func, LLVM.Value[dumfunc, newargs, cgnargs])
    # error("Not supported, yet")
end

function setup_builtins!(cg::CodeCtx)
    builtin = Dict{Symbol, LLVM.Function}()
    function add_builtin_func(a, b)
        func_type = LLVM.FunctionType(
            jl_value_t_ptr, 
            LLVMType[#=F=#     jl_value_t_ptr, 
                     #=args=#  jl_value_t_ptr_ptr, 
                     #=nargs=# uint32_t])
        func = LLVM.Function(cg.mod, string(b), func_type)
        LLVM.linkage!(func, LLVM.API.LLVMExternalLinkage)
        builtin[Symbol(a)] = func
    end
    add_builtin_func("===", :jl_f_is);
    add_builtin_func("typeof", :jl_f_typeof);
    add_builtin_func("sizeof", :jl_f_sizeof);
    add_builtin_func("<:", :jl_f_issubtype);
    add_builtin_func("isa", :jl_f_isa);
    add_builtin_func("typeassert", :jl_f_typeassert);
    add_builtin_func("throw", :jl_f_throw);
    add_builtin_func("tuple", :jl_f_tuple);

    # // field access
    add_builtin_func("getfield",  :jl_f_getfield);
    add_builtin_func("setfield!",  :jl_f_setfield);
    add_builtin_func("fieldtype", :jl_f_fieldtype);
    add_builtin_func("nfields", :jl_f_nfields);
    add_builtin_func("isdefined", :jl_f_isdefined);

    # // array primitives
    add_builtin_func("arrayref", :jl_f_arrayref);
    add_builtin_func("arrayset", :jl_f_arrayset);
    add_builtin_func("arraysize", :jl_f_arraysize);

    # // method table utils
    add_builtin_func("applicable", :jl_f_applicable);
    add_builtin_func("invoke", :jl_f_invoke);

    # // internal functions
    add_builtin_func("apply_type", :jl_f_apply_type);
    add_builtin_func("_apply", :jl_f__apply);
    add_builtin_func("_apply_pure", :jl_f__apply_pure);
    add_builtin_func("_apply_latest", :jl_f__apply_latest);
    add_builtin_func("_expr", :jl_f__expr);
    add_builtin_func("svec", :jl_f_svec);

    return builtin
end
