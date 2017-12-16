# Wrap builders with logging


# Adapted from MikeInnis MacroTools @forward
# https://github.com/MikeInnes/MacroTools.jl/blob/732cf05dd34fffacd44c6f5d41fb43d84199381d/src/examples/forward.jl
# macro logwrap(fs...)  
# #   fs = isexpr(fs, :tuple) ? map(esc, fs.args) : [esc(fs)]
#   :($([:(LLVM.$f(x, args...) = (Base.@_inline_meta; llvmoutput = LLVM.$f(x.builder, args...); @debug "$f" llvmoutput; llvmoutput))
#        for f in fs]...);
#     nothing)
# end

# @logwrap add!, alloca!, and!, array_alloca!, ashr!, bitcast!, br!, call!, extract_value!, fadd!, fcmp!, fdiv!, fmul!, fneg!, fpext!, fptosi!, fptoui!, fptrunc!, frem!, fsub!, gep!, icmp!, load!, mul!, neg!, not!, or!, position!, ret!, sdiv!, select!, sext!, sitofp!, srem!, store!, struct_gep!, sub!, trunc!, udiv!, uitofp!, urem!, xor!, zext!, 
fns =  [:add!, :alloca!, :and!, :array_alloca!, :ashr!, :bitcast!, :br!, :call!, :dispose, :extract_value!, 
        :fadd!, :fcmp!, :fdiv!, :fmul!, :fneg!, :fpext!, :fptosi!, :fptoui!, :fptrunc!, :frem!, :fsub!, 
        :gep!, :globalstring_ptr!, :icmp!, :load!, :lshr!, :mul!, :neg!, :not!, :or!, :position, :position!, 
        :ret!, :sdiv!, :select!, :sext!, :shl!, :sitofp!, :srem!, :store!, :struct_gep!, :sub!, 
        :trunc!, :udiv!, :uitofp!, :unreachable!, :urem!, :xor!, :zext!,]
for f in fns
    @eval LLVM.$f(x::LoggingBuilder, args...) = (Base.@_inline_meta; O = LLVM.$f(x.builder, args...); @debug "LLVM output" O; O)
end