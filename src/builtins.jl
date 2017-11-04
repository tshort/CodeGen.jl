
#
# Code generation for builtin functions and for boxing and unboxing.
# 

function emit_builtin!(cg::CodeCtx, name, jlargs, typ)
    # contains(string(name), "throw") && return cg.extern[:jl_void_type_g]  # Bail out on errors for now
    nargs = length(jlargs)
    if name == :(===) && nargs == 2
        # if isbits(args[1]) && typeof(args[1]) == typeof(args[2])
            # if isa(args[1], Integer)
                # Need to box result?
                return emit_intrinsic!(cg, :eq_int, jlargs)
            # end
        # end
    end 
    if name == :getfield && isbits(cg, jlargs[1])
        v = codegen!(cg, jlargs[1])
        @debug "$(cg.name): getfield" jlargs _typeof(cg, jlargs[2])
        if _typeof(cg, jlargs[2]) <: Integer 
            idx = jlargs[2]
        elseif _typeof(cg, jlargs[2]) <: QuoteNode
            idx = findfirst(equalto(nameof(jlargs[2])), fieldnames(cg, jlargs[1]))
            idx > 0 || error("a problem with getfield")
        else
            error("problem with getfield")
        end
        return LLVM.extract_value!(cg.builder, v, idx - 1)
    end
    if name == :tuple && isbits(typ)
        @debug "$(cg.name): emitting tuple of isbits $typ"
        loc = alloca!(cg.builder, llvmtype(typ))
        for i in 1:length(jlargs)
            p = LLVM.struct_gep!(cg.builder, loc, i-1)
            store!(cg, codegen!(cg, jlargs[i]), p)
        end
        return LLVM.load!(cg.builder, loc)
    end
    # Otherwise default to the C++ versions of these.
    @debug "$(cg.name): builtin"  typ jlargs 
    cgnargs = codegen!(cg, UInt32(nargs))
    newargs = LLVM.array_alloca!(cg.builder, jl_value_t_ptr, cgnargs)
    for i in 1:nargs
        v = emit_box!(cg, jlargs[i])
        p = LLVM.gep!(cg.builder, newargs, [codegen!(cg, i-1)])
        store!(cg, v, p)
    end
    func = cg.builtin[name]
    return LLVM.call!(cg.builder, func, LLVM.Value[emit_box!(cg, Int32(0)), newargs, cgnargs])
    # error("Not supported, yet")
end

emit_val!(cg::CodeCtx, v) = LLVM.llvmtype(v) == int1_t ? LLVM.zext!(cg.builder, v, int8_t) : v

# Make a custom `store!` to handle Bool/i1 values and stuff that shouldn't store
function store!(cg::CodeCtx, v, p)
    newv = emit_val!(cg, v)
    @debug "$(cg.name): store " newv v p
    if newv != cg.datatype[Tuple{}]
        return LLVM.store!(cg.builder, newv, p)
    end
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
