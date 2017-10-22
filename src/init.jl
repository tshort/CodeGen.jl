

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
    
    #
    # Functions
    # 
    e[:jl_box_int64_f] = extern!(mod, "jl_box_int64", jl_value_t_ptr, LLVMType[uint64_t])
    e[:jl_box_int8_f] = extern!(mod, "jl_box_int8", jl_value_t_ptr, LLVMType[uint8_t])
    
    e[:jl_unbox_int64_f] = extern!(mod, "jl_unbox_int8", uint8_t, LLVMType[jl_value_t_ptr])
    
    e[:jl_apply_array_type_f] = extern!(mod, "jl_apply_array_type", jl_value_t_ptr, LLVMType[jl_value_t_ptr, int32_t])
    
    e[:jl_new_struct_uninit_f] = extern!(mod, "jl_new_struct_uninit", jl_value_t_ptr, LLVMType[jl_datatype_t_ptr])
    
    return e
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
    jdt = eval(name)
    if haskey(cg.datatype, name)
        dt = cg.datatype[name]
    else
        jtype = eval(name)
            # JL_DLLEXPORT jl_datatype_t *jl_new_datatype(jl_sym_t *name,
            #                                     jl_module_t *module,
            #                                     jl_datatype_t *super,
            #                                     jl_svec_t *parameters,
            #                                     jl_svec_t *fnames, jl_svec_t *ftypes,
            #                                     int abstract, int mutabl,
            #                                     int ninitialized);
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
        dt = emit_new_datatype!(cg, args[1])
    end
    return dt
end