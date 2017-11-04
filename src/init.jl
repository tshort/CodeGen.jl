# 
# Sets up global values for LLVM types, Julia types, external declarations, and other utilities.
# 

const ctx = LLVM.Context(convert(LLVM.API.LLVMContextRef, cglobal(:jl_LLVMContext, Void)))

# Convert a Julia type to an LLVM type
# Note that LLVM.llvmtype returns the LLVM type of an LLVM value (could combine?)
llvmtype(x) = 
    LLVMType(ccall(:julia_type_to_llvm, LLVM.API.LLVMTypeRef, (Any, Bool), x, false))
    
#
# Includes some external definitions to functions and constants in julia.h
# 

#
# Types
# 
const jl_value_t_ptr = llvmtype(Any)
const jl_value_t = eltype(jl_value_t_ptr)
const jl_value_t_ptr_ptr = LLVM.PointerType(jl_value_t_ptr)
# cheat on these for now:
const jl_datatype_t_ptr = jl_value_t_ptr
const jl_unionall_t_ptr = jl_value_t_ptr 
const jl_typename_t_ptr = jl_value_t_ptr 
const jl_sym_t_ptr = jl_value_t_ptr 
const jl_svec_t_ptr = jl_value_t_ptr 
const jl_module_t_ptr = jl_value_t_ptr 
const jl_array_t_ptr = jl_value_t_ptr 

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
const void_t_ptr  = LLVM.PointerType(void_t)


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
    e[:jl_box_ssavalue]  = extern!(mod, "jl_box_ssavalue", jl_value_t_ptr, LLVMType[size_t])
    e[:jl_box_slotnumber]  = extern!(mod, "jl_box_slotnumber", jl_value_t_ptr, LLVMType[size_t])
    e[:jl_box_voidpointer]  = extern!(mod, "jl_box_voidpointer", jl_value_t_ptr, LLVMType[size_t])
    e[:jl_unbox_voidpointer]  = extern!(mod, "jl_unbox_voidpointer", void_t_ptr, LLVMType[jl_value_t_ptr])
    
    e[:jl_apply_array_type] = extern!(mod, "jl_apply_array_type", jl_value_t_ptr, LLVMType[jl_value_t_ptr, int32_t])
    e[:jl_apply_tuple_type] = extern!(mod, "jl_apply_tuple_type", jl_value_t_ptr, LLVMType[jl_svec_t_ptr])
    e[:jl_new_struct_uninit] = extern!(mod, "jl_new_struct_uninit", jl_value_t_ptr, LLVMType[jl_datatype_t_ptr])
    e[:jl_new_struct] = extern!(mod, "jl_new_struct", jl_value_t_ptr, LLVMType[jl_datatype_t_ptr], vararg = true)
    e[:jl_new_bits] = extern!(mod, "jl_new_bits", jl_value_t_ptr, LLVMType[jl_value_t_ptr, jl_value_t_ptr])
    e[:jl_set_nth_field] = extern!(mod, "jl_set_nth_field", void_t, LLVMType[jl_value_t_ptr, int32_t, jl_value_t_ptr])
    e[:jl_pchar_to_string] = extern!(mod, "jl_pchar_to_string", jl_value_t_ptr, LLVMType[int8_t_ptr, uint32_t])
    
    e[:jl_symbol] = extern!(mod, "jl_symbol", jl_sym_t_ptr, LLVMType[int8_t_ptr])
    e[:jl_svec] = extern!(mod, "jl_svec", jl_svec_t_ptr, LLVMType[], vararg = true)
    e[:jl_new_datatype] = extern!(mod, "jl_new_datatype", jl_datatype_t_ptr, 
        LLVMType[jl_sym_t_ptr, jl_module_t_ptr, jl_datatype_t_ptr, jl_svec_t_ptr, jl_svec_t_ptr, jl_svec_t_ptr, int32_t, int32_t, int32_t])
    # For intrinsics
    e[:jl_array_len_] = extern!(mod, "jl_array_len_", jl_datatype_t_ptr, LLVMType[jl_array_t_ptr])
    for i in [Int8,Int16,Int32,Int64,Int128]
        li = llvmtype(i)
        for funsym in [:bswap,:ctpop]
            name = Symbol("llvm.", funsym, ".", li)
            e[name] = extern!(mod, string(name), li, LLVMType[li])
        end 
        name = Symbol("llvm.ctlz.", li)
        e[name] = extern!(mod, string(name), li, LLVMType[li, int1_t])
    end 
    for fp in [Float32,Float64]
        lfp = llvmtype(fp)
        fps = fp == Float64 ? "f64" : "f32"
        for funsym in [:fabs,:ceil,:floor,:trunc,:rint,:sqrt]
            name = Symbol("llvm.", funsym, ".", fps)
            e[name] = extern!(mod, string(name), lfp, LLVMType[lfp])
        end 
        name = Symbol("llvm.fmuladd.", fps)
        e[name] = extern!(mod, string(name), lfp, LLVMType[lfp, lfp, lfp])
    end 

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
    setup_type!(jl_datatype_t_ptr, "jl_typeofbottom_type", Core.TypeofBottom)
    setup_type!(jl_datatype_t_ptr, "jl_datatype_type", DataType)
    setup_type!(jl_datatype_t_ptr, "jl_uniontype_type", Union)
    setup_type!(jl_datatype_t_ptr, "jl_unionall_type", UnionAll)
    setup_type!(jl_datatype_t_ptr, "jl_tvar_type"#= , TypeVar =#)
    setup_type!(jl_datatype_t_ptr, "jl_any_type", Any)
    setup_type!(jl_unionall_t_ptr, "jl_type_type", Type)
    setup_type!(jl_unionall_t_ptr, "jl_typetype_type", Type{Type})
    setup_type!(jl_value_t_ptr,    "jl_ANY_flag"#=, ANY =#)
    setup_type!(jl_datatype_t_ptr, "jl_typename_type", TypeName)
    setup_type!(jl_typename_t_ptr, "jl_type_typename", Type{TypeName})
    setup_type!(jl_datatype_t_ptr, "jl_sym_type", Symbol)
    setup_type!(jl_datatype_t_ptr, "jl_symbol_type", Symbol)
    setup_type!(jl_datatype_t_ptr, "jl_ssavalue_type", SSAValue)
    setup_type!(jl_datatype_t_ptr, "jl_abstractslot_type", Slot)
    setup_type!(jl_datatype_t_ptr, "jl_slotnumber_type", SlotNumber)
    setup_type!(jl_datatype_t_ptr, "jl_typedslot_type", TypedSlot)
    setup_type!(jl_datatype_t_ptr, "jl_simplevector_type", SimpleVector)
    setup_type!(jl_typename_t_ptr, "jl_tuple_typename", Tuple)
    setup_type!(jl_typename_t_ptr, "jl_vecelement_typename", VecElement)
    setup_type!(jl_datatype_t_ptr, "jl_anytuple_type", Tuple)
    setup_type!(jl_datatype_t_ptr, "jl_emptytuple_type", Tuple{})
    setup_type!(jl_unionall_t_ptr, "jl_anytuple_type_type")
    setup_type!(jl_unionall_t_ptr, "jl_vararg_type", Vararg)
    setup_type!(jl_typename_t_ptr, "jl_vararg_typename")
    setup_type!(jl_datatype_t_ptr, "jl_task_type", Task)
    setup_type!(jl_datatype_t_ptr, "jl_function_type", Function)
    setup_type!(jl_datatype_t_ptr, "jl_builtin_type", Core.Builtin)
    setup_type!(jl_value_t_ptr   , "jl_bottom_type")
    setup_type!(jl_datatype_t_ptr, "jl_method_instance_type", Core.MethodInstance)
    setup_type!(jl_datatype_t_ptr, "jl_code_info_type", CodeInfo)
    setup_type!(jl_datatype_t_ptr, "jl_method_type", Method)
    setup_type!(jl_datatype_t_ptr, "jl_module_type", Module)
    setup_type!(jl_unionall_t_ptr, "jl_abstractarray_type", AbstractArray)
    setup_type!(jl_unionall_t_ptr, "jl_densearray_type", DenseArray)
    setup_type!(jl_unionall_t_ptr, "jl_array_type", Array)
    setup_type!(jl_typename_t_ptr, "jl_array_typename")
    setup_type!(jl_datatype_t_ptr, "jl_weakref_type", WeakRef)
    setup_type!(jl_datatype_t_ptr, "jl_abstractstring_type", AbstractString)
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
    setup_type!(jl_datatype_t_ptr, "jl_floatingpoint_type", AbstractFloat)
    setup_type!(jl_datatype_t_ptr, "jl_number_type", Number)
    setup_type!(jl_datatype_t_ptr, "jl_void_type", Void)
    setup_type!(jl_datatype_t_ptr, "jl_signed_type", Signed)
    setup_type!(jl_datatype_t_ptr, "jl_voidpointer_type")
    setup_type!(jl_unionall_t_ptr, "jl_pointer_type", Ptr)
    setup_type!(jl_unionall_t_ptr, "jl_ref_type", Ref)
    setup_type!(jl_typename_t_ptr, "jl_pointer_typename")
    setup_type!(jl_value_t_ptr,    "jl_array_uint8_type")
    setup_type!(jl_value_t_ptr,    "jl_array_any_type")
    setup_type!(jl_value_t_ptr,    "jl_array_symbol_type")
    setup_type!(jl_datatype_t_ptr, "jl_expr_type")
    setup_type!(jl_datatype_t_ptr, "jl_globalref_type")
    setup_type!(jl_datatype_t_ptr, "jl_linenumbernode_type")
    setup_type!(jl_datatype_t_ptr, "jl_labelnode_type")
    setup_type!(jl_datatype_t_ptr, "jl_gotonode_type")
    setup_type!(jl_datatype_t_ptr, "jl_quotenode_type", QuoteNode)
    setup_type!(jl_datatype_t_ptr, "jl_newvarnode_type", NewvarNode)
    setup_type!(jl_datatype_t_ptr, "jl_intrinsic_type", Core.IntrinsicFunction)
    setup_type!(jl_datatype_t_ptr, "jl_methtable_type", MethodTable)
    setup_type!(jl_datatype_t_ptr, "jl_typemap_level_type", TypeMapLevel)
    setup_type!(jl_datatype_t_ptr, "jl_typemap_entry_type", TypeMapEntry)
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
