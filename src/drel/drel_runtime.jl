# These definitions enhance standard Julia definitions to bring
# function behaviour in line with dREL

# Include this file in any namespace (module) that evaluates Julia
# code derived from dREL

using LinearAlgebra

export drelvector,to_julia_array

# a character can be compared to a single-character string
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
Base.setindex!(a::drelvector,v,index) = setindex!(a.elements,v,index)
LinearAlgebra.cross(a::drelvector,b::drelvector) = drelvector(cross(vec(a.elements),vec(b.elements)))
# Broadcasting, so we get a drelvector when working with scalars
Base.BroadcastStyle(::Type{<:drelvector}) = Broadcast.ArrayStyle{drelvector}()
Base.similar(a::Broadcast.Broadcasted{Broadcast.ArrayStyle{drelvector}},::Type{ElType}) where ElType = drelvector(similar(Array{ElType},axes(a)))


#== Convert the dREL array representation to the Julia representation...
recursively. A dREL array is a sequence of potentially nested lists. Each
element is separated by a comma. This becomes, in Julia, a vector of
vectors, which is ultimately one-dimensional. So we loop over each element,
stacking each vector at each level into a 2-D array. Note that, while we
swap the row and column directions (dimensions 1 and 2) the rest are 
unchanged. Each invocation of this routine returns the actual level
that is currently being treated, together with the result of working
with the previous level.

Vectors in dREL are a bit magic, in that they conform themselves
to be row or column as required. We have implemented this in
the runtime, so we need to turn any single-dimensional array
into a drelvector ==#

to_julia_array(drel_array) = begin
    if ndims(drel_array) == 1 && eltype(drel_array) <: Number
        return drelvector(drel_array)
    else
        return to_julia_array_rec(drel_array)[2]
    end
end

to_julia_array_rec(drel_array) = begin
    if eltype(drel_array) <: AbstractArray   #can go deeper
        sep_arrays  = to_julia_array_rec.(drel_array)
        level = sep_arrays[1][1]  #level same everywhere
        result = (x->x[2]).(sep_arrays)
        if level == 2
            #println("$level:$result")
            return 3, vcat(result...)
        else
            #println("$level:$result")
            return level+1, cat(result...,dims=level)
        end
    else    #primitive elements, make them floats
        #println("Bottom level: $drel_array")
        return 2,hcat(Float64.(drel_array)...)
    end
end
