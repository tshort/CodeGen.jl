# # Sets up global values for LLVM types, Julia types, external declarations, and other utilities.
# 

# const ctx = LLVM.Context(convert(LLVM.API.LLVMContextRef, cglobal(:jl_LLVMContext, Void)))
const ctx = LLVM.GlobalContext()

# Convert a Julia type to an LLVM type
# Note that LLVM.llvmtype returns the LLVM type of an LLVM value (could combine?)
# llvmtype(x) = 
#     LLVMType(ccall(:julia_type_to_llvm, LLVM.API.LLVMTypeRef, (Any, Bool), x, false))
    
#
# Includes some external definitions to functions and constants in julia.h
# 

#
# Types
# 
# const jl_value_t_ptr = llvmtype(Any)
# const jl_value_t = eltype(jl_value_t_ptr)
const jl_value_t = LLVM.StructType("jl_value_t", ctx)
const jl_value_t_ptr = LLVM.PointerType(jl_value_t)
const jl_value_t_ptr_ptr = LLVM.PointerType(jl_value_t_ptr)
# cheat on these for now:
const jl_datatype_t_ptr = jl_value_t_ptr
const jl_unionall_t_ptr = jl_value_t_ptr 
const jl_typename_t_ptr = jl_value_t_ptr 
const jl_sym_t_ptr = jl_value_t_ptr 
const jl_svec_t_ptr = jl_value_t_ptr 
const jl_module_t_ptr = jl_value_t_ptr 

const tmap = Dict{Type,LLVM.LLVMType}(
    Void    => LLVM.VoidType(ctx),
    Bool    => LLVM.Int8Type(ctx),
    Int8    => LLVM.Int8Type(ctx),
    Int16   => LLVM.Int16Type(ctx),
    Int32   => LLVM.Int32Type(ctx),
    Int64   => LLVM.Int64Type(ctx),
    UInt8   => LLVM.Int8Type(ctx),
    UInt16  => LLVM.Int16Type(ctx),
    UInt32  => LLVM.Int32Type(ctx),
    UInt64  => LLVM.Int64Type(ctx),
    Float32 => LLVM.FloatType(ctx),
    Float64 => LLVM.DoubleType(ctx)
)
llvmtype(x) = get(tmap, x, jl_value_t_ptr)


const bool_t  = llvmtype(Bool)
const int1_t  = LLVM.Int1Type(ctx)
const int8_t  = llvmtype(Int8)
const int16_t = llvmtype(Int16)
const int32_t = llvmtype(Int32)
const int64_t = llvmtype(Int64)
const uint8_t  = llvmtype(UInt8)
const uint16_t = llvmtype(UInt16)
const uint32_t = llvmtype(UInt32)
const uint64_t = llvmtype(UInt64)
const float_t  = llvmtype(Float32)
const double_t = llvmtype(Float64)
const float32_t = llvmtype(Float32)
const float64_t = llvmtype(Float64)
const void_t    = llvmtype(Void)
const size_t    = llvmtype(Int)

const int8_t_ptr  = LLVM.PointerType(int8_t)


function extern_global!(mod, name, typ)
    res = LLVM.GlobalVariable(mod, typ, string(name))
    LLVM.linkage!(res, LLVM.API.LLVMExternalLinkage)
    return res
end

function extern!(mod, name, rettyp, argtypes; vararg = false)
    res = LLVM.Function(mod, string(name), LLVM.FunctionType(rettyp, argtypes, vararg))
    LLVM.linkage!(res, LLVM.API.LLVMExternalLinkage)
    return res
end

function setup_externs!(mod)
    e = Dict{Symbol, Any}()
    #
    # Global variables, not including type definitions
    # 

    e[:jl_main_module_g] = extern_global!(mod, "jl_main_module", jl_module_t_ptr)

    #
    # Functions
    # 
    for s in [:int64, :int32, :int16, :int8, :uint64, :uint32, :uint16, :uint8, :float64, :float32]
        #e[:jl_box_int64] = extern!(mod, "jl_box_int64", jl_value_t_ptr, LLVMType[int64_t])
        e[Symbol(:jl_box_, s)] = extern!(mod, "jl_box_$s", jl_value_t_ptr, LLVMType[eval(Symbol(s, :_t))])
        # e[:jl_unbox_int64] = extern!(mod, "jl_unbox_int64", int64_t, LLVMType[jl_value_t_ptr])
        e[Symbol(:jl_unbox_, s)] = extern!(mod, "jl_unbox_$s", eval(Symbol(s, :_t)), LLVMType[jl_value_t_ptr])
    end
    e[:jl_box_bool]  = extern!(mod, "jl_box_bool", jl_value_t_ptr, LLVMType[uint8_t])
    e[:jl_unbox_bool]  = extern!(mod, "jl_unbox_bool", uint8_t, LLVMType[jl_value_t_ptr])
    e[:jl_box_ssavalue]  = extern!(mod, "jl_ssavalue", jl_value_t_ptr, LLVMType[size_t])
    e[:jl_box_slotnumber]  = extern!(mod, "jl_slotnumber", jl_value_t_ptr, LLVMType[size_t])
    
    e[:jl_apply_array_type] = extern!(mod, "jl_apply_array_type", jl_value_t_ptr, LLVMType[jl_value_t_ptr, int32_t])
    e[:jl_new_struct_uninit] = extern!(mod, "jl_new_struct_uninit", jl_value_t_ptr, LLVMType[jl_datatype_t_ptr])
    e[:jl_set_nth_field] = extern!(mod, "jl_set_nth_field", void_t, LLVMType[jl_value_t_ptr, int32_t, jl_value_t_ptr])
    e[:jl_pchar_to_string] = extern!(mod, "jl_pchar_to_string", jl_value_t_ptr, LLVMType[int8_t_ptr, uint32_t])
    
    e[:jl_symbol] = extern!(mod, "jl_symbol", jl_sym_t_ptr, LLVMType[int8_t_ptr])
    e[:jl_svec] = extern!(mod, "jl_svec", jl_svec_t_ptr, LLVMType[], vararg = true)
    e[:jl_new_datatype] = extern!(mod, "jl_new_datatype", jl_datatype_t_ptr, 
        LLVMType[jl_sym_t_ptr, jl_module_t_ptr, jl_datatype_t_ptr, jl_svec_t_ptr, jl_svec_t_ptr, jl_svec_t_ptr, int32_t, int32_t, int32_t])
    e[:jl_new_abstracttype] = extern!(mod, "jl_new_abstracttype", jl_datatype_t_ptr, 
        LLVMType[jl_sym_t_ptr, jl_module_t_ptr, jl_datatype_t_ptr, jl_svec_t_ptr])

    return e
end

#
# Types
#

# TODO: fill in more
const type_g = Dict{Type, Symbol}(
    Void    => :jl_void_type_g,
    Bool    => :jl_bool_type_g,
    Int8    => :jl_int8_type_g,
    Int16   => :jl_int16_type_g,
    Int32   => :jl_int32_type_g,
    Int64   => :jl_int64_type_g,
    UInt8   => :jl_uint8_type_g,
    UInt16  => :jl_uint16_type_g,
    UInt32  => :jl_uint32_type_g,
    UInt64  => :jl_uint64_type_g,
    Float16 => :jl_float16_type_g,
    Float32 => :jl_float32_type_g,
    Float64 => :jl_float64_type_g
)

function setup_types!(cg)
    d = Dict{Type, Any}()
    function setup_type!(typ, name, jltyp=nothing)
        symname = Symbol(name*"_g")
        g = extern_global!(cg.mod, name, typ)
        if jltyp != nothing
            d[jltyp] = g
        end
        cg.extern[symname] = g
    end
    setup_type!(jl_datatype_t_ptr, "jl_typeofbottom_type")
    setup_type!(jl_datatype_t_ptr, "jl_datatype_type")
    setup_type!(jl_datatype_t_ptr, "jl_uniontype_type")
    setup_type!(jl_datatype_t_ptr, "jl_unionall_type")
    setup_type!(jl_datatype_t_ptr, "jl_tvar_type")
    setup_type!(jl_datatype_t_ptr, "jl_any_type", Any)
    setup_type!(jl_unionall_t_ptr, "jl_type_type")
    setup_type!(jl_unionall_t_ptr, "jl_typetype_type")
    setup_type!(jl_value_t_ptr,    "jl_ANY_flag")
    setup_type!(jl_datatype_t_ptr, "jl_typename_type")
    setup_type!(jl_typename_t_ptr, "jl_type_typename")
    setup_type!(jl_datatype_t_ptr, "jl_sym_type")
    setup_type!(jl_datatype_t_ptr, "jl_symbol_type", Symbol)
    setup_type!(jl_datatype_t_ptr, "jl_ssavalue_type")
    setup_type!(jl_datatype_t_ptr, "jl_abstractslot_type")
    setup_type!(jl_datatype_t_ptr, "jl_slotnumber_type")
    setup_type!(jl_datatype_t_ptr, "jl_typedslot_type")
    setup_type!(jl_datatype_t_ptr, "jl_simplevector_type")
    setup_type!(jl_typename_t_ptr, "jl_tuple_typename", Tuple)
    setup_type!(jl_typename_t_ptr, "jl_vecelement_typename")
    setup_type!(jl_datatype_t_ptr, "jl_anytuple_type")
    setup_type!(jl_datatype_t_ptr, "jl_emptytuple_type")
    setup_type!(jl_unionall_t_ptr, "jl_anytuple_type_type")
    setup_type!(jl_unionall_t_ptr, "jl_vararg_type")
    setup_type!(jl_typename_t_ptr, "jl_vararg_typename")
    setup_type!(jl_datatype_t_ptr, "jl_task_type")
    setup_type!(jl_datatype_t_ptr, "jl_function_type")
    setup_type!(jl_datatype_t_ptr, "jl_builtin_type")
    setup_type!(jl_value_t_ptr   , "jl_bottom_type")
    setup_type!(jl_datatype_t_ptr, "jl_method_instance_type")
    setup_type!(jl_datatype_t_ptr, "jl_code_info_type")
    setup_type!(jl_datatype_t_ptr, "jl_method_type")
    setup_type!(jl_datatype_t_ptr, "jl_module_type", Module)
    setup_type!(jl_unionall_t_ptr, "jl_abstractarray_type")
    setup_type!(jl_unionall_t_ptr, "jl_densearray_type")
    setup_type!(jl_unionall_t_ptr, "jl_array_type", Array)
    setup_type!(jl_typename_t_ptr, "jl_array_typename")
    setup_type!(jl_datatype_t_ptr, "jl_weakref_type")
    setup_type!(jl_datatype_t_ptr, "jl_abstractstring_type")
    setup_type!(jl_datatype_t_ptr, "jl_string_type", String)
    setup_type!(jl_datatype_t_ptr, "jl_errorexception_type", ErrorException)
    setup_type!(jl_value_t_ptr,    "jl_argumenterror_type", ArgumentError)
    setup_type!(jl_datatype_t_ptr, "jl_loaderror_type", LoadError)
    setup_type!(jl_datatype_t_ptr, "jl_initerror_type", InitError)
    setup_type!(jl_datatype_t_ptr, "jl_typeerror_type", TypeError)
    setup_type!(jl_datatype_t_ptr, "jl_methoderror_type", MethodError)
    setup_type!(jl_datatype_t_ptr, "jl_undefvarerror_type", UndefVarError)
    setup_type!(jl_value_t_ptr, "jl_stackovf_exception", StackOverflowError)
    setup_type!(jl_value_t_ptr, "jl_memory_exception", OutOfMemoryError)
    setup_type!(jl_value_t_ptr, "jl_readonlymemory_exception")
    setup_type!(jl_value_t_ptr, "jl_diverror_exception", DivideError)
    setup_type!(jl_value_t_ptr, "jl_undefref_exception", UndefRefError)
    setup_type!(jl_value_t_ptr, "jl_interrupt_exception", InterruptException)
    setup_type!(jl_datatype_t_ptr, "jl_boundserror_type", BoundsError)
    setup_type!(jl_value_t_ptr, "jl_an_empty_vec_any")
    setup_type!(jl_datatype_t_ptr, "jl_bool_type", Bool)
    setup_type!(jl_datatype_t_ptr, "jl_char_type", Char)
    setup_type!(jl_datatype_t_ptr, "jl_int8_type", Int8)
    setup_type!(jl_datatype_t_ptr, "jl_uint8_type", UInt8)
    setup_type!(jl_datatype_t_ptr, "jl_int16_type", Int16)
    setup_type!(jl_datatype_t_ptr, "jl_uint16_type", UInt16)
    setup_type!(jl_datatype_t_ptr, "jl_int32_type", Int32)
    setup_type!(jl_datatype_t_ptr, "jl_uint32_type", UInt32)
    setup_type!(jl_datatype_t_ptr, "jl_int64_type", Int64)
    setup_type!(jl_datatype_t_ptr, "jl_uint64_type", UInt64)
    setup_type!(jl_datatype_t_ptr, "jl_float16_type", Float16)
    setup_type!(jl_datatype_t_ptr, "jl_float32_type", Float32)
    setup_type!(jl_datatype_t_ptr, "jl_float64_type", Float64)
    setup_type!(jl_datatype_t_ptr, "jl_floatingpoint_type")
    setup_type!(jl_datatype_t_ptr, "jl_number_type")
    setup_type!(jl_datatype_t_ptr, "jl_void_type", Void)
    setup_type!(jl_datatype_t_ptr, "jl_signed_type")
    setup_type!(jl_datatype_t_ptr, "jl_voidpointer_type")
    setup_type!(jl_unionall_t_ptr, "jl_pointer_type")
    setup_type!(jl_unionall_t_ptr, "jl_ref_type")
    setup_type!(jl_typename_t_ptr, "jl_pointer_typename")
    setup_type!(jl_value_t_ptr,    "jl_array_uint8_type")
    setup_type!(jl_value_t_ptr,    "jl_array_any_type")
    setup_type!(jl_value_t_ptr,    "jl_array_symbol_type")
    setup_type!(jl_datatype_t_ptr, "jl_expr_type")
    setup_type!(jl_datatype_t_ptr, "jl_globalref_type")
    setup_type!(jl_datatype_t_ptr, "jl_linenumbernode_type")
    setup_type!(jl_datatype_t_ptr, "jl_labelnode_type")
    setup_type!(jl_datatype_t_ptr, "jl_gotonode_type")
    setup_type!(jl_datatype_t_ptr, "jl_quotenode_type")
    setup_type!(jl_datatype_t_ptr, "jl_newvarnode_type")
    setup_type!(jl_datatype_t_ptr, "jl_intrinsic_type")
    setup_type!(jl_datatype_t_ptr, "jl_methtable_type")
    setup_type!(jl_datatype_t_ptr, "jl_typemap_level_type")
    setup_type!(jl_datatype_t_ptr, "jl_typemap_entry_type")
    setup_type!(jl_svec_t_ptr,  "jl_emptysvec")
    setup_type!(jl_value_t_ptr, "jl_emptytuple")
    setup_type!(jl_value_t_ptr, "jl_true")
    setup_type!(jl_value_t_ptr, "jl_false")
    setup_type!(jl_value_t_ptr, "jl_nothing")
    setup_type!(jl_sym_t_ptr,   "jl_incomplete_sym")
    return d
end


#
# More utilities
# 
has_terminator(bb::BasicBlock) =
    LLVM.API.LLVMGetBasicBlockTerminator(LLVM.blockref(bb)) != C_NULL


#
# DataType - emit and return a stored type or create a new type and store it
#
function load_and_emit_datatype!(cg, ::Type{JT}) where JT

    if haskey(cg.datatype, JT)
        return LLVM.load!(cg.builder, cg.datatype[JT])
    end
    
    # error("Not supported, yet")
    ## Everything past here is unfinished / untested
    lname = emit_symbol!(cg, JT.name)
    
    mod = LLVM.load!(cg.builder, cg.extern[:jl_main_module_g])
    super = load_and_emit_datatype!(cg, JT.super)
    params = LLVM.call!(cg.builder, cg.extern[:jl_svec], 
        LLVM.Value[codegen!(cg, length(JT.parameters)), [load_and_emit_datatype!(cg, t) for t in JT.parameters]...])
    if !isconcrete(JT)
        dt = LLVM.call!(cg.builder, cg.extern[:jl_new_abstracttype], LLVM.Value[lname, mod, super, params])
    else
        fnames = LLVM.call!(cg.builder, cg.extern[:jl_svec], 
            LLVM.Value[codegen!(cg, length(fieldnames(JT))), [emit_symbol!(cg, s) for s in fieldnames(JT)]...])
        ftypes = LLVM.call!(cg.builder, cg.extern[:jl_svec], 
            LLVM.Value[codegen!(cg, length(JT.types)), [load_and_emit_datatype!(cg, t) for t in JT.types]...])
        abstrct = codegen!(cg, UInt32(JT.abstract))
        mutabl = JT.mutable ? codegen!(cg, UInt32(1)) : codegen!(cg, UInt32(0))
        ninitialized = codegen!(cg, UInt32(JT.ninitialized))
        dt = LLVM.call!(cg.builder, cg.extern[:jl_new_datatype], 
            LLVM.Value[lname, mod, super, params, fnames, ftypes, abstrct, mutabl, ninitialized])
            # LLVMType[jl_sym_t_ptr, jl_module_t_ptr, jl_datatype_t_ptr, jl_svec_t_ptr, jl_svec_t_ptr, jl_svec_t_ptr, int32_t, int32_t, int32_t])
    end
    loc = LLVM.GlobalVariable(cg.mod, jl_datatype_t_ptr, string(JT))
    sdt = LLVM.store!(cg.builder, dt, loc)
    cg.datatype[JT] = sdt
    return LLVM.load!(cg.builder, loc)
end

load_and_emit_datatype!(cg, x::GlobalRef) = load_and_emit_datatype!(cg, eval(x))

load_and_emit_datatype!(cg, x) = codegen!(cg, x)

emit_symbol!(cg, x) =
    LLVM.call!(cg.builder, cg.extern[:jl_symbol], [globalstring_ptr!(cg.builder, string(x))])
