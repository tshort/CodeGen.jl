#
# Code generation for intrinsic functions.
# 

make_intrinsic_arg!(cg, x) = codegen!(cg, x)
make_intrinsic_arg!(cg, x::Type{T}) where {T} = llvmtype(x)
make_intrinsic_arg!(cg, x::GlobalRef) = make_intrinsic_arg!(cg, eval(x))

function uint_cnvt!(cg, to, x)
    t = LLVM.llvmtype(x)
    t == to && return x
    width(to) < width(t) && return LLVM.trunc!(cg.builder, x, to)
    return LLVM.zext!(cg.builder, x, to)
end

function emit_intrinsic!(cg::CodeCtx, name, jlargs)
    args = Any[]
    for v in jlargs
        push!(args, make_intrinsic_arg!(cg, v))
    end
    name == :neg_int  && return LLVM.neg!(cg.builder, args[1])
    name == :add_int  && return LLVM.add!(cg.builder, args[1], args[2])
    name == :sub_int  && return LLVM.sub!(cg.builder, args[1], args[2])
    name == :mul_int  && return LLVM.mul!(cg.builder, args[1], args[2])
    name == :sdiv_int && return LLVM.sdiv!(cg.builder, args[1], args[2])
    name == :udiv_int && return LLVM.udiv!(cg.builder, args[1], args[2])
    name == :srem_int && return LLVM.srem!(cg.builder, args[1], args[2])
    name == :urem_int && return LLVM.urem!(cg.builder, args[1], args[2])
    name == :neg_float  && return LLVM.fsub!(cg.builder, codegen!(cg, -0.0), args[1])
    name == :add_float  && return LLVM.fadd!(cg.builder, args[1], args[2])
    name == :sub_float  && return LLVM.fsub!(cg.builder, args[1], args[2])
    name == :mul_float  && return LLVM.fmul!(cg.builder, args[1], args[2])
    name == :div_float  && return LLVM.fdiv!(cg.builder, args[1], args[2])
    name == :rem_float  && return LLVM.frem!(cg.builder, args[1], args[2])
    ## WRONG. Not sure how to do these. Need a new builder with fast math set.
    name == :neg_float_fast  && return LLVM.fneg!(cg.builder, args[1])
    name == :add_float_fast  && return LLVM.fadd!(cg.builder, args[1], args[2])
    name == :sub_float_fast  && return LLVM.fsub!(cg.builder, args[1], args[2])
    name == :mul_float_fast  && return LLVM.fmul!(cg.builder, args[1], args[2])
    name == :div_float_fast  && return LLVM.fdiv!(cg.builder, args[1], args[2])
    name == :rem_float_fast  && return LLVM.frem!(cg.builder, args[1], args[2])
    ## More tough ones
    # name == :fma_float  && return LLVM.frem!(cg.builder, args[1], args[2], "sremtmp")

    function ltyp(x)
        res = string(LLVM.llvmtype(x))
        if res == "double"
            res = "f64"
        elseif res == "float"
            res = "f32"
        end
        return res
    end
    
    name == :muladd_float  && return LLVM.call!(cg.builder, 
        cg.extern[Symbol("llvm.fmuladd.$(ltyp(args[1]))")], 
        LLVM.Value[args[1], args[2], args[3]])


    function checked_int(sym)
        ifun = cg.extern[Symbol("llvm.$sym.with.overflow.$(ltyp(args[1]))")] 
        res = LLVM.call!(cg.builder, ifun, LLVM.Value[args[1], args[2]])
        val = LLVM.extract_value!(cg.builder, res, 0)
        obit = LLVM.extract_value!(cg.builder, res, 1)
        obyte = LLVM.zext!(cg.builder, obit, int8_t)
        tupptr = alloca!(cg.builder, LLVM.StructType([LLVM.llvmtype(args[1]), int8_t], CodeGen.ctx))
        store!(cg, val,   LLVM.struct_gep!(cg.builder, tupptr, 0))
        store!(cg, obyte, LLVM.struct_gep!(cg.builder, tupptr, 1))
        return LLVM.load!(cg.builder, tupptr)
    end

    name == :checked_sadd_int  && return checked_int(:sadd)
    name == :checked_uadd_int  && return checked_int(:uadd)
    name == :checked_ssub_int  && return checked_int(:ssub)
    name == :checked_usub_int  && return checked_int(:usub)
    name == :checked_smul_int  && return checked_int(:smul)
    name == :checked_umul_int  && return checked_int(:umul)
    # name == :checked_sdiv_int  && return LLVM.sdiv!(cg.builder, args[1], args[2])
    # name == :checked_udiv_int  && return LLVM.udiv!(cg.builder, args[1], args[2])
    # name == :checked_srem_int  && return LLVM.srem!(cg.builder, args[1], args[2])
    # name == :checked_urem_int  && return LLVM.urem!(cg.builder, args[1], args[2])
    ##

    emit_bool!(x) = LLVM.zext!(cg.builder, x, int8_t)
    emit_icmp!(fun) = emit_bool!(LLVM.icmp!(cg.builder, fun, args[1], args[2]))
    emit_fcmp!(fun) = emit_bool!(LLVM.fcmp!(cg.builder, fun, args[1], args[2]))
    name == :eq_int  && return emit_icmp!(LLVM.API.LLVMIntEQ)
    name == :ne_int  && return emit_icmp!(LLVM.API.LLVMIntNE)
    name == :slt_int && return emit_icmp!(LLVM.API.LLVMIntSLT)
    name == :ult_int && return emit_icmp!(LLVM.API.LLVMIntULT)
    name == :sle_int && return emit_icmp!(LLVM.API.LLVMIntSLE)
    name == :ule_int && return emit_icmp!(LLVM.API.LLVMIntULE)
    name == :eq_float && return emit_fcmp!(LLVM.API.LLVMRealOEQ)
    name == :ne_float && return emit_fcmp!(LLVM.API.LLVMRealONE)
    name == :lt_float && return emit_fcmp!(LLVM.API.LLVMRealOLT)
    name == :le_float && return emit_fcmp!(LLVM.API.LLVMRealOLE)
    ## need fast versions of above
    # fpiseq
    # fpislt
    name == :and_int  && return emit_bool!(LLVM.and!(cg.builder, args[1], args[2]))
    name == :or_int   && return emit_bool!(LLVM.or!(cg.builder, args[1], args[2]))
    name == :xor_int  && return emit_bool!(LLVM.xor!(cg.builder, args[1], args[2]))

    a1(name) = LLVM.call!(cg.builder, cg.extern[Symbol("llvm.$name.$(ltyp(args[1]))")], LLVM.Value[args[1]])

    name == :bswap_int  && return a1("bswap")
    name == :ctpop_int  && return a1("ctpop")
    name == :abs_float  && return a1("fabs")
    name == :ceil_llvm  && return a1("ceil")
    name == :floor_llvm && return a1("floor")
    name == :trunc_llvm && return a1("trunc")
    name == :rint_llvm  && return a1("rint")
    name == :sqrt_llvm  && return a1("sqrt")

    name == :ctlz_int  && return LLVM.call!(cg.builder, 
        cg.extern[Symbol("llvm.ctlz.$(ltyp(args[1]))")], 
        LLVM.Value[args[1], LLVM.ConstantInt(int1_t, 0)])
 
    # cttz_int
    # copysign_float
    if name == :flipsign_int 
        # ignores the constant case
        tmp = LLVM.ashr!(cg.builder, args[2], codegen!(cg, LLVM.width(LLVM.llvmtype(args[1])) - 1))
        return LLVM.xor!(cg.builder, LLVM.add!(cg.builder, args[1], tmp), tmp)
    end

    name == :sitofp  && return LLVM.sitofp!(cg.builder, args[2], args[1])
    name == :uitofp  && return LLVM.uitofp!(cg.builder, args[2], args[1])
    name == :fptosi  && return LLVM.fptosi!(cg.builder, args[2], args[1])
    name == :fptoui  && return LLVM.fptoui!(cg.builder, args[2], args[1])
    name == :trunc_int  && return LLVM.trunc!(cg.builder, args[2], args[1])
    name == :fptrunc    && return LLVM.fptrunc!(cg.builder, args[2], args[1])
    name == :fpext      && return LLVM.fpext!(cg.builder, args[2], args[1])
    name == :sext_int   && return LLVM.sext!(cg.builder, args[2], args[1])
    name == :zext_int   && return LLVM.zext!(cg.builder, args[2], args[1])
    name == :fpzext     && return LLVM.fpext!(cg.builder, args[2], args[1])
    if name == :arraylen  
        p = LLVM.bitcast!(cg.builder, args[1], LLVM.PointerType(llvmtype(Tuple{Ptr{Void}, Csize_t})))
        len_p = LLVM.struct_gep!(cg.builder, p, 1)
        return LLVM.load!(cg.builder, len_p)
    end

    function emit_sh!(fun)
        t1 = LLVM.llvmtype(args[1])
        t2 = LLVM.llvmtype(args[2])
        return LLVM.select!(cg.builder, 
                            LLVM.icmp!(cg.builder, LLVM.API.LLVMIntUGE, args[2], LLVM.ConstantInt(t2, width(t1))),
                            LLVM.ConstantInt(t1, 0),
                            fun(cg.builder, args[1], uint_cnvt!(cg, t1, args[2])))
    end
    name == :shl_int  && return emit_sh!(LLVM.shl!)
    name == :ashr_int && return emit_sh!(LLVM.ashr!)
    name == :lshr_int && return emit_sh!(LLVM.lshr!)

    ######
    ## NOT UNIVERSAL, but maybe useful for getting a few things to work
    name == :select_value && return LLVM.select!(cg.builder, emit_condition!(cg, args[1]), args[2], args[3])
    name == :not_int      && return emit_bool!(LLVM.not!(cg.builder, emit_condition!(cg, args[1])))
    name == :bitcast      && return LLVM.bitcast!(cg.builder, args[2], args[1])  # not completely general

    ######
    name == :add_ptr && return LLVM.ptrtoint!(cg.builder, 
                                              LLVM.gep!(cg.builder, 
                                                        LLVM.inttoptr!(cg.builder, args[1], int8_t_ptr), 
                                                        [args[2]]), 
                                              LLVM.llvmtype(args[1])) 
    name == :sub_ptr && return LLVM.ptrtoint!(cg.builder, 
                                              LLVM.gep!(cg.builder, 
                                                        LLVM.inttoptr!(cg.builder, args[1], int8_t_ptr), 
                                                        [LLVM.neg!(cg.builder, args[2])]), 
                                              LLVM.llvmtype(args[1]))

    ######
    # name == :pointerref && return LLVM.call!(cg.builder, cg.extern[:jl_pointerref], LLVM.Value[emit_box!(cg, args[1]), emit_box!(cg, args[2]), emit_box!(cg, args[3])])
    # name == :pointerset && return LLVM.call!(cg.builder, cg.extern[:jl_pointerset], LLVM.Value[emit_box!(cg, args[1]), emit_box!(cg, args[2]), emit_box!(cg, args[3]), emit_box!(cg, args[4])])
    name == :pointerref && return LLVM.call!(cg.builder, cg.extern[:jl_pointerref], LLVM.Value[args[1], args[2], args[3]])
    name == :pointerset && return LLVM.call!(cg.builder, cg.extern[:jl_pointerset], LLVM.Value[args[1], args[2], args[3], args[4]])

    error("Unsupported intrinsic: $name")
end

