
#
# Code generation for boxing and unboxing.
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
    if T <: LLVM.Value   # BROKEN
        return emit_box!(cg, LLVM.llvmtype(x), x)
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