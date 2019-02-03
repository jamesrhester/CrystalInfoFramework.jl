# These definitions override standard Julia definitions to bring
# function behaviour in line with dREL

# Include this file in any namespace (module) that evaluates Julia
# code derived from dREL

# getindex of a string produces a character
using LinearAlgebra

Base.:(==)(c::Char,y::String) = begin
    if length(y) == 1
        return c == y[1]
    else
        return false
    end
end

Base.:(+)(y::String,z::String) = y*z

# We redefine vectors so that we can fix up post and pre
# multiplication to always work

struct drelvector <: AbstractVector{Number}
    elements::Array{Number,1}
end

# postmultiply: no transpose necessary
Base.:(*)(a::Array,b::drelvector) = begin
    #println("Multiplying $a by $(b.elements)")
    res = drelvector(a * b.elements)
    #println("To get $res")
    return res
end

# premultiply: transpose first
Base.:(*)(a::drelvector,b::Array) = drelvector(transpose(a) * b)

# join multiply: dot product
Base.:(*)(a::drelvector,b::drelvector) = dot(a.elements,b.elements)

# all the rest
Base.getindex(a::drelvector,b) = getindex(a.elements,b)
Base.length(a::drelvector) = length(a.elements)
Base.size(a::drelvector) = size(a.elements)
LinearAlgebra.cross(a::drelvector,b::drelvector) = cross(vec(a.elements),vec(b.elements))
