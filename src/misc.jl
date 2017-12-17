
# Wrap builders with logging
fns =  [:add!, :alloca!, :and!, :array_alloca!, :ashr!, :bitcast!, :br!, :call!, :dispose, :extract_value!, 
        :fadd!, :fcmp!, :fdiv!, :fmul!, :fneg!, :fpext!, :fptosi!, :fptoui!, :fptrunc!, :frem!, :fsub!, 
        :gep!, :globalstring_ptr!, :icmp!, :load!, :lshr!, :mul!, :neg!, :not!, :or!, :position, :position!, 
        :ret!, :sdiv!, :select!, :sext!, :shl!, :sitofp!, :srem!, :store!, :struct_gep!, :sub!, 
        :trunc!, :udiv!, :uitofp!, :unreachable!, :urem!, :xor!, :zext!,]
for f in fns
    @eval LLVM.$f(x::LoggingBuilder, args...) = (Base.@_inline_meta; O = LLVM.$f(x.builder, args...); @debug "LLVM output" O; O)
end


export basedump
basedump(@nospecialize(fun), @nospecialize(argtypes)) = 
    print(Base._dump_function(fun, argtypes, false, true, false, true, :att, false))
