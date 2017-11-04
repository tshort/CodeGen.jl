#
# Code generation for builtin functions and for boxing and unboxing.
# 

emit_box!(cg::CodeCtx, ::Type{Any}, v) = v
emit_box!(cg::CodeCtx, ::Type{T}, v) where {T} = v

emit_box!(cg::CodeCtx, ::Type{Bool}, v) = LLVM.call!(cg.builder, cg.extern[:jl_box_bool], LLVM.Value[emit_val!(cg, v)])
emit_box!(cg::CodeCtx, ::Type{Int8}, v)  = LLVM.call!(cg.builder, cg.extern[:jl_box_int8], LLVM.Value[v])
emit_box!(cg::CodeCtx, ::Type{Int16}, v) = LLVM.call!(cg.builder, cg.extern[:jl_box_int16], LLVM.Value[v])
emit_box!(cg::CodeCtx, ::Type{Int32}, v) = LLVM.call!(cg.builder, cg.extern[:jl_box_int32], LLVM.Value[v])
emit_box!(cg::CodeCtx, ::Type{Int64}, v) = LLVM.call!(cg.builder, cg.extern[:jl_box_int64], LLVM.Value[v])
emit_box!(cg::CodeCtx, ::Type{Float32}, v) = LLVM.call!(cg.builder, cg.extern[:jl_box_float32], LLVM.Value[v])
emit_box!(cg::CodeCtx, ::Type{Float64}, v) = LLVM.call!(cg.builder, cg.extern[:jl_box_float64], LLVM.Value[v])
emit_box!(cg::CodeCtx, ::Type{SSAValue}, v) = LLVM.call!(cg.builder, cg.extern[:jl_box_ssavalue], LLVM.Value[v])
emit_box!(cg::CodeCtx, ::Type{SlotNumber}, v) = LLVM.call!(cg.builder, cg.extern[:jl_box_slotnumber], LLVM.Value[v])

# function emit_box!(cg::CodeCtx, ::Type{T}, v) where T <: Tuple
# #   params = jl_svec(n_args, arg1_type, arg2_type, ...);
# #   tuple_type = jl_apply_tuple_type(params);
# #   result = jl_new_struct(tuple_type, jl_box...(arg1), jl_box...(arg2), ...);
#     if !isbits(T)
#         return v
#     end
#     println("Boxing a bits-type tuple")
#     n = length(T.parameters)
#     dt = LLVM.call!(cg.builder, cg.extern[:jl_apply_tuple_type], 
#                     LLVM.call!(cg.builder, cg.extern[:jl_svec], codegen!(cg, Cint(n)), 
#                                load_and_emit_datatype!.(cg, collect(T.parameters))...))
#     llvmargs = LLVM.Value[dt]
#     for i in 1:n
#         push!(llvmargs, codegen!(cg, x)) # need gep, load, store
#     end
#     return LLVM.call!(cg.builder, cg.extern[:jl_new_struct], llvmargs)
# end

function emit_box!(cg::CodeCtx, @nospecialize(x::T)) where T
    isa(x, Type)         && return cg.datatype[x]
    v = codegen!(cg, x)
    @debug "$(cg.name): boxing " x v
    T == Any && return v
    T <: Base.BitInteger && return emit_box!(cg, T, v)
    T <: Base.IEEEFloat  && return emit_box!(cg, T, v)
    T == Bool            && return emit_box!(cg, T, v)
    # T == SSAValue        && return emit_box!(cg, T, codegen!(cg, x.id))
    # T == SlotNumber      && return emit_box!(cg, T, codegen!(cg, x.id))
    if T == SlotNumber 
        slottype = cg.code_info.slottypes[x.id]
        # if isbits(slottype) 
            return emit_box!(cg, slottype, v)
        # else
        #     return v
        # end
    end
    if T == SSAValue
        ssatype = cg.code_info.ssavaluetypes[x.id+1] # I think the first position is a placeholder
        @debug "$(cg.name): boxing SSAValue $(x.id)" ssatype 
        if isbits(ssatype)
            return emit_box!(cg, ssatype, v) 
        else
            return v
        end
    end
    if T == Expr
        # if isbits(x.typ) 
            return emit_box!(cg, x.typ, v)
        # else
        #     return v
        # end
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
        if T <: Tuple && isbits(T)
            bcp = LLVM.bitcast!(cg.builder, v, LLVM.PointerType(llvmtype(T)))
            return LLVM.load!(cg.builder, bcp)
        end
    end
    return v
end

Base.isbits(cg::CodeCtx, x) = false
Base.isbits(cg::CodeCtx, x::SlotNumber) = isbits(cg.code_info.slottypes[x.id])
Base.isbits(cg::CodeCtx, x::SSAValue) = isbits(cg.code_info.ssavaluetypes[x.id + 1])
Base.isbits(cg::CodeCtx, x::Expr) = isbits(x.typ)
Base.fieldnames(cg::CodeCtx, x::SlotNumber) = fieldnames(cg.code_info.slottypes[x.id])
Base.fieldnames(cg::CodeCtx, x::SSAValue) = fieldnames(cg.code_info.ssavaluetypes[x.id + 1])
Base.fieldnames(cg::CodeCtx, x::Expr) = fieldnames(x.typ)
_typeof(cg::CodeCtx, x::SlotNumber) = cg.code_info.slottypes[x.id]
_typeof(cg::CodeCtx, x::SSAValue) = cg.code_info.ssavaluetypes[x.id + 1]
_typeof(cg::CodeCtx, x::Expr) = x.typ
_typeof(cg::CodeCtx, x) = Base.typeof(x)
_typeof(cg::CodeCtx, x::GlobalRef) = Any

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
        @debug "getfield" jlargs _typeof(cg, jlargs[2])
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

# Make a custom `store!` to handle Bool/i1 values
store!(cg::CodeCtx, v, p) = LLVM.store!(cg.builder, emit_val!(cg, v), p)


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
