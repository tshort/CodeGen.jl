

const ctx = LLVM.Context(convert(LLVM.API.LLVMContextRef, cglobal(:jl_LLVMContext, Void)))

# Convert a Julia type to an LLVM type
# Note that LLVM.llvmtype returns the LLVM type of an LLVM value (could combine?)
llvmtype(x) = 
    LLVMType(ccall(:julia_type_to_llvm, LLVM.API.LLVMTypeRef, (Any, Bool), x, false))

const bool_t  = llvmtype(Bool)
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


#
# Includes some external definitions to functions and constants in julia.h
# 

#
# Types
# 
const jl_value_t = LLVM.StructType("jl_value_t", ctx)
const jl_value_t_ptr = llvmtype(Any)
const jl_value_t_ptr_ptr = LLVM.PointerType(jl_value_t_ptr)
const jl_datatype_t_ptr = jl_value_t_ptr # cheat on this for now


function setup_externs!(mod)
    e = Dict{Symbol, Any}()
    #
    # Global variables, including type definitions
    # 
    e[:jl_array_type_g] = LLVM.GlobalVariable(mod, jl_value_t_ptr, "jl_array_type")
    LLVM.linkage!(e[:jl_array_type_g], LLVM.API.LLVMExternalLinkage)
    
    #
    # Functions
    # 
    e[:jl_box_int64_f] = LLVM.Function(mod, "jl_box_int64", LLVM.FunctionType(jl_value_t_ptr, LLVMType[llvmtype(Int64)]))
    LLVM.linkage!(e[:jl_box_int64_f], LLVM.API.LLVMExternalLinkage)
    e[:jl_box_int8_f] = LLVM.Function(mod, "jl_box_int8", LLVM.FunctionType(jl_value_t_ptr, LLVMType[llvmtype(Int8)]))
    LLVM.linkage!(e[:jl_box_int8_f], LLVM.API.LLVMExternalLinkage)
    
    e[:jl_unbox_int64_f] = LLVM.Function(mod, "jl_unbox_int64", LLVM.FunctionType(llvmtype(Int64), LLVMType[jl_value_t_ptr]))
    LLVM.linkage!(e[:jl_unbox_int64_f], LLVM.API.LLVMExternalLinkage)
    
    e[:jl_apply_array_type_f] =
        LLVM.Function(mod, "jl_apply_array_type", 
                      LLVM.FunctionType(jl_value_t_ptr, LLVM.LLVMType[jl_value_t_ptr, llvmtype(Int32)]))
    LLVM.linkage!(e[:jl_apply_array_type_f], LLVM.API.LLVMExternalLinkage)
    
    e[:jl_new_struct_uninit_f] = LLVM.Function(mod, "jl_new_struct_uninit", 
        LLVM.FunctionType(jl_value_t_ptr, LLVMType[jl_datatype_t_ptr]))
    LLVM.linkage!(e[:jl_new_struct_uninit_f], LLVM.API.LLVMExternalLinkage)
    
    return e
end


#
# More utilities
# 
has_terminator(bb::BasicBlock) =
    LLVM.API.LLVMGetBasicBlockTerminator(LLVM.blockref(bb)) != C_NULL