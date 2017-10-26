#
# Code generation for builtin functions and for boxing and unboxing.
# 

emit_box!(cg::CodeCtx, ::Type{Any}, v) = v

emit_box!(cg::CodeCtx, ::Type{Bool}, v)  = LLVM.call!(cg.builder, cg.extern[:jl_box_bool], LLVM.Value[v])
emit_box!(cg::CodeCtx, ::Type{Int8}, v)  = LLVM.call!(cg.builder, cg.extern[:jl_box_int8], LLVM.Value[v])
emit_box!(cg::CodeCtx, ::Type{Int16}, v) = LLVM.call!(cg.builder, cg.extern[:jl_box_int16], LLVM.Value[v])
emit_box!(cg::CodeCtx, ::Type{Int32}, v) = LLVM.call!(cg.builder, cg.extern[:jl_box_int32], LLVM.Value[v])
emit_box!(cg::CodeCtx, ::Type{Int64}, v) = LLVM.call!(cg.builder, cg.extern[:jl_box_int64], LLVM.Value[v])
emit_box!(cg::CodeCtx, ::Type{Float32}, v) = LLVM.call!(cg.builder, cg.extern[:jl_box_float32], LLVM.Value[v])
emit_box!(cg::CodeCtx, ::Type{Float64}, v) = LLVM.call!(cg.builder, cg.extern[:jl_box_float64], LLVM.Value[v])
emit_box!(cg::CodeCtx, ::Type{SSAValue}, v) = LLVM.call!(cg.builder, cg.extern[:jl_box_ssavalue], LLVM.Value[v])
emit_box!(cg::CodeCtx, ::Type{SlotNumber}, v) = LLVM.call!(cg.builder, cg.extern[:jl_box_slotnumber], LLVM.Value[v])

function emit_box!(cg::CodeCtx, @nospecialize(x::T)) where T
    v = codegen!(cg, x)
    T == Any && return v
    T <: Base.BitInteger && return emit_box!(cg, T, v)
    T <: Base.IEEEFloat  && return emit_box!(cg, T, v)
    T == Bool            && return emit_box!(cg, T, v)
    T == SSAValue        && return emit_box!(cg, T, codegen!(cg, x.id))
    T == SlotNumber      && return emit_box!(cg, T, codegen!(cg, x.id))
    if T == Expr
        if isbits(x.typ) 
            return emit_box!(cg, x.typ, v)
        else
            return v
        end
    end
    return v
    error("Boxing of $T not supported")
end
# emit_box!(cg::CodeCtx, v, t::LLVM.PointerType) = v

function emit_unbox!(cg::CodeCtx, v, ::Type{T}) where T
    t = LLVM.llvmtype(v) 
    if t == jl_value_t_ptr 
        T == Bool  && return LLVM.call!(cg.builder, cg.extern[:jl_unbox_bool], LLVM.Value[v])
        T == Int8  && return LLVM.call!(cg.builder, cg.extern[:jl_unbox_int8], LLVM.Value[v])
        T == Int16 && return LLVM.call!(cg.builder, cg.extern[:jl_unbox_int16], LLVM.Value[v])
        T == Int32 && return LLVM.call!(cg.builder, cg.extern[:jl_unbox_int32], LLVM.Value[v])
        T == Int64 && return LLVM.call!(cg.builder, cg.extern[:jl_unbox_int64], LLVM.Value[v])
        T == Float32 && return LLVM.call!(cg.builder, cg.extern[:jl_unbox_float32], LLVM.Value[v])
        T == Float64 && return LLVM.call!(cg.builder, cg.extern[:jl_unbox_float64], LLVM.Value[v])
    end
    return v
end


function emit_builtin!(cg::CodeCtx, name, jlargs)
    nargs = length(jlargs)
    if name == :(===) && nargs == 2
        # if isbits(args[1]) && typeof(args[1]) == typeof(args[2])
            # if isa(args[1], Integer)
                # Need to box result?
                return emit_intrinsic!(cg, :eq_int, jlargs)
            # end
        # end
    end 
    # Otherwise default to the C++ versions of these.
    cgnargs = codegen!(cg, UInt32(nargs))
    newargs = LLVM.array_alloca!(cg.builder, jl_value_t_ptr, cgnargs)
    for i in 1:nargs
        v = emit_box!(cg, jlargs[i])
        p = LLVM.gep!(cg.builder, newargs, [codegen!(cg, i-1)])
        LLVM.store!(cg.builder, v, p)
    end
    func = cg.builtin[name]
    return LLVM.call!(cg.builder, func, LLVM.Value[emit_box!(cg, Int32(0)), newargs, cgnargs])
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
