

const ctx = LLVM.Context(convert(LLVM.API.LLVMContextRef, cglobal(:jl_LLVMContext, Void)))
const active_module = LLVM.Module("JuliaCodeGenModule", ctx)

llvmtype(x) = 
    LLVMType(ccall(:julia_type_to_llvm, LLVM.API.LLVMTypeRef, (Any, Bool), x, false))

const jl_value_t = LLVM.StructType("jl_value_t", ctx)
const jl_value_t_ptr = llvmtype(Any)
const jl_value_t_ptr_ptr = LLVM.PointerType(jl_value_t_ptr)

const jl_box_int64_f = LLVM.Function(active_module, "jl_box_int64", LLVM.FunctionType(jl_value_t_ptr, LLVMType[llvmtype(Int64)]))
LLVM.linkage!(jl_box_int64_f, LLVM.API.LLVMExternalLinkage)
const jl_box_int8_f = LLVM.Function(active_module, "jl_box_int8", LLVM.FunctionType(jl_value_t_ptr, LLVMType[llvmtype(Int8)]))
LLVM.linkage!(jl_box_int8_f, LLVM.API.LLVMExternalLinkage)

const jl_unbox_int64_f = LLVM.Function(active_module, "jl_unbox_int64", LLVM.FunctionType(llvmtype(Int64), LLVMType[jl_value_t_ptr]))
LLVM.linkage!(jl_unbox_int64_f, LLVM.API.LLVMExternalLinkage)

const jl_apply_array_type_f =
    LLVM.Function(active_module, "jl_apply_array_type", 
                  LLVM.FunctionType(jl_value_t_ptr, LLVM.LLVMType[jl_value_t_ptr, llvmtype(Int32)]))
LLVM.linkage!(jl_apply_array_type_f, LLVM.API.LLVMExternalLinkage)

const jl_new_struct_uninit_f = LLVM.Function(active_module, "jl_new_struct_uninit_f", 
    LLVM.FunctionType(llvmtype(Int64), LLVMType[jl_value_t_ptr]))
LLVM.linkage!(jl_new_struct_uninit_f, LLVM.API.LLVMExternalLinkage)


const jl_array_type_g = LLVM.GlobalVariable(active_module, jl_value_t_ptr, "jl_array_type")
LLVM.linkage!(jl_array_type_g, LLVM.API.LLVMExternalLinkage)


has_terminator(bb::BasicBlock) =
    LLVM.API.LLVMGetBasicBlockTerminator(LLVM.blockref(bb)) != C_NULL
