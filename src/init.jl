

const ctx = LLVM.Context(convert(LLVM.API.LLVMContextRef, cglobal(:jl_LLVMContext, Void)))

# Convert a Julia type to an LLVM type
# Note that LLVM.llvmtype returns the LLVM type of an LLVM value (could combine?)
llvmtype(x) = 
    LLVMType(ccall(:julia_type_to_llvm, LLVM.API.LLVMTypeRef, (Any, Bool), x, false))
    

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

const int8_t_ptr  = LLVM.PointerType(int8_t)


#
# Includes some external definitions to functions and constants in julia.h
# 

#
# Types
# 
const jl_value_t = LLVM.StructType("jl_value_t", ctx)
const jl_value_t_ptr = llvmtype(Any)
const jl_value_t_ptr_ptr = LLVM.PointerType(jl_value_t_ptr)
# cheat on these for now:
const jl_datatype_t_ptr = jl_value_t_ptr
const jl_unionall_t_ptr = jl_value_t_ptr 
const jl_typename_t_ptr = jl_value_t_ptr 
const jl_sym_t_ptr = jl_value_t_ptr 
const jl_svec_t_ptr = jl_value_t_ptr 

function extern_global!(mod, name, typ)
    res = LLVM.GlobalVariable(mod, typ, string(name))
    LLVM.linkage!(res, LLVM.API.LLVMExternalLinkage)
    return res
end

function extern!(mod, name, rettyp, argtypes)
    res = LLVM.Function(mod, string(name), LLVM.FunctionType(rettyp, argtypes))
    LLVM.linkage!(res, LLVM.API.LLVMExternalLinkage)
    return res
end

function setup_externs!(mod)
    e = Dict{Symbol, Any}()
    #
    # Global variables, including type definitions
    # 
    e[:jl_array_type_g] = extern_global!(mod, "jl_array_type", jl_value_t_ptr)
    e[:jl_any_type_g] = extern_global!(mod, "jl_any_type", jl_datatype_t_ptr)
    #
    # Functions
    # 
    e[:jl_box_int64_f] = extern!(mod, "jl_box_int64", jl_value_t_ptr, LLVMType[uint64_t])
    e[:jl_box_int8_f] = extern!(mod, "jl_box_int8", jl_value_t_ptr, LLVMType[uint8_t])
    
    e[:jl_unbox_int64_f] = extern!(mod, "jl_unbox_int64", uint64_t, LLVMType[jl_value_t_ptr])
    
    e[:jl_apply_array_type_f] = extern!(mod, "jl_apply_array_type", jl_value_t_ptr, LLVMType[jl_value_t_ptr, int32_t])
    e[:jl_new_struct_uninit_f] = extern!(mod, "jl_new_struct_uninit", jl_value_t_ptr, LLVMType[jl_datatype_t_ptr])
    e[:jl_set_nth_field_f] = extern!(mod, "jl_set_nth_field", void_t, LLVMType[jl_value_t_ptr, int32_t, jl_value_t_ptr])
    e[:jl_pchar_to_string_f] = extern!(mod, "jl_pchar_to_string", jl_value_t_ptr, LLVMType[int8_t_ptr, uint32_t])

    return e
end

#
# Types
#

function setup_types!(cg)
    d = Dict{Symbol, Any}()
    function setup_type!(typ, name, sym=nothing)
        symname = Symbol(name*"_g")
        g = extern_global!(cg.mod, name, typ)
        if sym != nothing
            d[sym] = g
        end
        cg.extern[symname] = g
    end
    setup_type!(jl_datatype_t_ptr, "jl_typeofbottom_type")
    setup_type!(jl_datatype_t_ptr, "jl_datatype_type")
    setup_type!(jl_datatype_t_ptr, "jl_uniontype_type")
    setup_type!(jl_datatype_t_ptr, "jl_unionall_type")
    setup_type!(jl_datatype_t_ptr, "jl_tvar_type")
    setup_type!(jl_datatype_t_ptr, "jl_any_type", :Any)
    setup_type!(jl_unionall_t_ptr, "jl_type_type")
    setup_type!(jl_unionall_t_ptr, "jl_typetype_type")
    setup_type!(jl_value_t_ptr,    "jl_ANY_flag")
    setup_type!(jl_datatype_t_ptr, "jl_typename_type")
    setup_type!(jl_typename_t_ptr, "jl_type_typename")
    setup_type!(jl_datatype_t_ptr, "jl_sym_type")
    setup_type!(jl_datatype_t_ptr, "jl_symbol_type", :Symbol)
    setup_type!(jl_datatype_t_ptr, "jl_ssavalue_type")
    setup_type!(jl_datatype_t_ptr, "jl_abstractslot_type")
    setup_type!(jl_datatype_t_ptr, "jl_slotnumber_type")
    setup_type!(jl_datatype_t_ptr, "jl_typedslot_type")
    setup_type!(jl_datatype_t_ptr, "jl_simplevector_type")
    setup_type!(jl_typename_t_ptr, "jl_tuple_typename", :Tuple)
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
    setup_type!(jl_datatype_t_ptr, "jl_module_type", :Module)
    setup_type!(jl_unionall_t_ptr, "jl_abstractarray_type")
    setup_type!(jl_unionall_t_ptr, "jl_densearray_type")
    setup_type!(jl_unionall_t_ptr, "jl_array_type", :Array)
    setup_type!(jl_typename_t_ptr, "jl_array_typename")
    setup_type!(jl_datatype_t_ptr, "jl_weakref_type")
    setup_type!(jl_datatype_t_ptr, "jl_abstractstring_type")
    setup_type!(jl_datatype_t_ptr, "jl_string_type", :String)
    setup_type!(jl_datatype_t_ptr, "jl_errorexception_type", :ErrorException)
    setup_type!(jl_datatype_t_ptr, "jl_argumenterror_type", :ArgumentError)
    setup_type!(jl_datatype_t_ptr, "jl_loaderror_type", :LoadError)
    setup_type!(jl_datatype_t_ptr, "jl_initerror_type", :InitError)
    setup_type!(jl_datatype_t_ptr, "jl_typeerror_type", :TypeError)
    setup_type!(jl_datatype_t_ptr, "jl_methoderror_type", :MethodError)
    setup_type!(jl_datatype_t_ptr, "jl_undefvarerror_type", :UndefVarError)
    setup_type!(jl_value_t_ptr, "jl_stackovf_exception", :StackOverflowError)
    setup_type!(jl_value_t_ptr, "jl_memory_exception", :OutOfMemoryError)
    setup_type!(jl_value_t_ptr, "jl_readonlymemory_exception")
    setup_type!(jl_value_t_ptr, "jl_diverror_exception", :DivideError)
    setup_type!(jl_value_t_ptr, "jl_undefref_exception", :UndefRefError)
    setup_type!(jl_value_t_ptr, "jl_interrupt_exception", :InterruptException)
    setup_type!(jl_datatype_t_ptr, "jl_boundserror_type", :BoundsError)
    setup_type!(jl_value_t_ptr, "jl_an_empty_vec_any")
    setup_type!(jl_datatype_t_ptr, "jl_bool_type")
    setup_type!(jl_datatype_t_ptr, "jl_char_type")
    setup_type!(jl_datatype_t_ptr, "jl_int8_type")
    setup_type!(jl_datatype_t_ptr, "jl_uint8_type")
    setup_type!(jl_datatype_t_ptr, "jl_int16_type")
    setup_type!(jl_datatype_t_ptr, "jl_uint16_type")
    setup_type!(jl_datatype_t_ptr, "jl_int32_type")
    setup_type!(jl_datatype_t_ptr, "jl_uint32_type")
    setup_type!(jl_datatype_t_ptr, "jl_int64_type")
    setup_type!(jl_datatype_t_ptr, "jl_uint64_type")
    setup_type!(jl_datatype_t_ptr, "jl_float16_type")
    setup_type!(jl_datatype_t_ptr, "jl_float32_type")
    setup_type!(jl_datatype_t_ptr, "jl_float64_type")
    setup_type!(jl_datatype_t_ptr, "jl_floatingpoint_type")
    setup_type!(jl_datatype_t_ptr, "jl_number_type")
    setup_type!(jl_datatype_t_ptr, "jl_void_type")
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
# DataType
#
function get_and_emit_datatype!(cg, name)
    if haskey(cg.datatype, name) 
        return cg.datatype[name]
    end
    error("Not supported, yet")
    ## Everything past here is broken
    jtype = eval(name)
        # JL_DLLEXPORT jl_datatype_t_ptr jl_new_datatype(jl_sym_t_ptr name,
        #                                     jl_module_t_ptr module,
        #                                     jl_datatype_t_ptr super,
        #                                     jl_svec_t_ptr parameters,
        #                                     jl_svec_t_ptr fnames, jl_svec_t_ptr ftypes,
        #                                     int abstract, int mutabl,
        #                                     int ninitialized)
    lname = LLVM.call!(cg.builder, cg.extern[:jl_symbol_f], [sname])
    mod = cg.extern[:jl_main_module_g]
    super = get_and_emit_datatype!(cg, jdt.super.name)
    # params = 
    # fnames = 
    # ftypes = 
    abstrct = codegen!(cg, UInt32(jdt.abstract))
    mutabl = jdt.mutable ? codegen!(cg, UInt32(1)) : codegen!(cg, UInt32(1))
    ninitialized = codegen!(cg, UInt32(jdt.ninitialized))
    dt = LLVM.call!(cg.builder, cg.extern[:jl_new_datatype_f], 
        LLVM.Value[lname, mod, super, params, fnames, ftypes, abstrct, mutabl, ninitialized])
    cg.datatype[name] = dt
    return dt
end