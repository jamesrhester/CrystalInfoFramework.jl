
# **Caseless strings
#
# We need caseless strings for the dictionaries, in order to allow
# caseless comparisons.
#
#

export CaselessString

"""
A string which ignores case
"""
struct CaselessString <: AbstractString
    actual_string::String
end

Base.:(==)(a::CaselessString,b::CaselessString) = lowercase(a)==lowercase(b)
Base.:(==)(a::SubString{CaselessString},b::SubString{CaselessString}) = lowercase(a)==lowercase(b)

# == CaselessString == #

Base.lowercase(a::CaselessString) = lowercase(a.actual_string)
Base.uppercase(a::CaselessString) = uppercase(a.actual_string)

Base.:(==)(a::CaselessString,b::AbstractString) = lowercase(a) == lowercase(b)
Base.:(==)(a::AbstractString,b::CaselessString) = lowercase(a) == lowercase(b)
Base.:(==)(a::SubString{CaselessString},b::AbstractString) = lowercase(a) == lowercase(b)
Base.:(==)(a::SubString{CaselessString},b::CaselessString) = lowercase(a) == lowercase(b)
Base.:(==)(a::AbstractString,b::SubString{CaselessString}) = lowercase(a) == lowercase(b)
Base.:(==)(a::CaselessString,b::SubString{CaselessString}) = lowercase(a) == lowercase(b)

Base.iterate(c::CaselessString) = iterate(c.actual_string)
Base.iterate(c::CaselessString,s::Integer) = iterate(c.actual_string,s)
Base.ncodeunits(c::CaselessString) = ncodeunits(c.actual_string)
Base.isvalid(c::CaselessString,i::Integer) = isvalid(c.actual_string,i)
Base.codeunit(c::CaselessString) = codeunit(c.actual_string)
Base.show(io::IO,c::CaselessString) = show(io,c.actual_string)

#== A caseless string should match both upper and lower case ==#

Base.getindex(d::Dict{String,V} where V,key::Union{CaselessString,SubString{CaselessString}}) = begin
    for (k,v) in d
        if lowercase(k) == lowercase(key)
            return v
        end
    end
    KeyError("$key not found")
end

Base.haskey(d::Dict{CaselessString,V} where V,key) = lowercase(key) in keys(d) 
#
Base.hash(c::CaselessString,h::UInt) = hash(lowercase(c.actual_string),h)
