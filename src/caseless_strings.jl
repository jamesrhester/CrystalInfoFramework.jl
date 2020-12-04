
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

# == CaselessString == #

Base.:(==)(a::CaselessString,b::AbstractString) = begin
    lowercase(a.actual_string) == lowercase(b)
end

Base.:(==)(a::AbstractString,b::CaselessString) = begin
    lowercase(a) == lowercase(b.actual_string)
end

Base.:(==)(a::CaselessString,b::CaselessString) = lowercase(a)==lowercase(b)
Base.:(==)(a::SubString{CaselessString},b::SubString{CaselessString}) = lowercase(a)==lowercase(b)

#== the following don't work, for now we have explicit types 
Base.:(==)(a::AbstractString,b::SubString{T} where {T}) = a == T(b)

Base.:(==)(a::SubString{T} where {T},b::AbstractString) = T(a) == b
==#

Base.:(==)(a::SubString{CaselessString},b::AbstractString) = CaselessString(a) == b
Base.:(==)(a::AbstractString,b::SubString{CaselessString}) = CaselessString(b) == a
Base.:(==)(a::CaselessString,b::SubString{CaselessString}) = a == CaselessString(b)

Base.iterate(c::CaselessString) = iterate(c.actual_string)
Base.iterate(c::CaselessString,s::Integer) = iterate(c.actual_string,s)
Base.ncodeunits(c::CaselessString) = ncodeunits(c.actual_string)
Base.isvalid(c::CaselessString,i::Integer) = isvalid(c.actual_string,i)
Base.codeunit(c::CaselessString) = codeunit(c.actual_string)

#== A caseless string should match both upper and lower case ==#

Base.getindex(d::Dict{String,Any},key::SubString{CaselessString}) = begin
    for (k,v) in d
        if lowercase(k) == lowercase(key)
            return v
        end
    end
    KeyError("$key not found")
end

Base.haskey(d::Dict{CaselessString,Any},key) = haskey(d,lowercase(key)) 
#
Base.show(io::IO,c::CaselessString) = show(io,c.actual_string)
Base.hash(c::CaselessString,h::UInt) = hash(lowercase(c.actual_string),h)
