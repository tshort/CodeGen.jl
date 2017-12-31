
# Wrap builders with logging
fns =  [:add!, :alloca!, :and!, :array_alloca!, :ashr!, :bitcast!, :br!, :call!, :dispose, :extract_value!, 
        :fadd!, :fcmp!, :fdiv!, :fmul!, :fneg!, :fpext!, :fptosi!, :fptoui!, :fptrunc!, :frem!, :fsub!, 
        :gep!, :globalstring_ptr!, :icmp!, :inttoptr!, :load!, :lshr!, :mul!, :neg!, :not!, :or!, :position, 
        :position!, :ptrtoint!,
        :ret!, :sdiv!, :select!, :sext!, :shl!, :sitofp!, :srem!, :store!, :struct_gep!, :sub!, 
        :trunc!, :udiv!, :uitofp!, :unreachable!, :urem!, :xor!, :zext!]
for f in fns
    @eval LLVM.$f(x::LoggingBuilder, args...) = (Base.@_inline_meta; O = LLVM.$f(x.builder, args...); @debug "LLVM output for $(x.name):" O; O)
end


export basedump
basedump(@nospecialize(fun), @nospecialize(argtypes)) = 
    print(Base._dump_function(fun, argtypes, false, true, false, true, :att, false))

# Temporary workaround for an LLVM bug
function LLVM.ConstantInt(typ::LLVM.IntegerType, val::UInt64)
    bits = reinterpret(Culonglong, val)
    return LLVM.ConstantInt(LLVM.API.LLVMConstInt(LLVM.ref(typ), bits, convert(LLVM.Bool, false)))
end