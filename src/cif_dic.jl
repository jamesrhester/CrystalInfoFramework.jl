# **CIF Dictionaries

export get_names_in_cat,AbstractCifDictionary,has_drel_methods
export convert_to_julia
export get_container_type

"""
A dictionary providing type and other information about a series
of data names.
"""
abstract type AbstractCifDictionary end

Base.length(d::AbstractCifDictionary) = begin
    return length(keys(d))
end

"""
    has_drel_methods(d)

Does `d` include methods written in dREL for derivation of data
values?
"""
has_drel_methods(d::AbstractCifDictionary) = true

"""
    get_names_in_cat(d::AbstractCifDictionary,catname;aliases=false,only_items=true)

Return a list of all names in `catname`, as defined in `d`. If `aliases`, include any
declared aliases of the name. If `only_items` is false, return child categories as
well.
"""
get_names_in_cat(d::AbstractCifDictionary,catname;aliases=false,only_items=true) = begin
    all_objs  = get_objs_in_cat(d,catname)
    canonical_names = [find_name(d,catname,x) for x in all_objs]
    if only_items filter!(x->!is_category(d,x),canonical_names) end
    if aliases
        search_names = copy(canonical_names)
        for n in search_names
            append!(canonical_names,list_aliases(d,n))
        end
    end
    return canonical_names
end

"""
    convert_to_julia(cdic,cat,obj,value::Array)

Convert elements of array `value` to the appropriate Julia type 
using information in `cdic` for given `category` and `object`, unless
value is `missing` or `nothing`, which are returned unchanged.
This only handles one level of arrays. `value` must be either an
`Array{CifValue,1}` (usually `Array{String,}`) or of the correct type
already.
"""
convert_to_julia(cdic,cat,obj,value::Array) = begin
    julia_base_type,cont_type = get_julia_type_name(cdic,cat,obj)
    if typeof(value) == Array{julia_base_type,1} return value end
    #if !(eltype(value) <: CifValue)
    #    throw(error("Unable to convert values of type $(eltype(value))"))
    #end
    change_func = (x->x)
    #println("Julia type for $cat/$obj is $julia_base_type, converting $value")
    if julia_base_type == Integer
        change_func = (x -> map(y-> if ismissing(y) || isnothing(y) y else parse(Int,y) end,x))
    elseif julia_base_type == Float64
        change_func = (x -> map(y->real_from_meas(y),x))
    elseif julia_base_type == Complex
        change_func = (x -> map(y-> if ismissing(y) || isnothing(y) y else parse(Complex{Float64},y) end,x))   #TODO: SU on values
    elseif julia_base_type in (String,AbstractString)
        change_func = (x -> map(y-> if ismissing(y) || isnothing(y) y else String(y) end,x))
    elseif julia_base_type == :CaselessString
        change_func = (x -> map(y-> if ismissing(y) || isnothing(y) y else CaselessString(y) end,x))
    end
    if cont_type == "Single"
        return change_func(value)
    elseif cont_type in ["Array", "Matrix", "List"]
        return map(change_func,value)
    else error("Unsupported container type $cont_type")   #we can do nothing
    end
end

"""
    convert_to_julia(cdic,dataname,value)

Convert String elements of array `value` to the appropriate Julia type
using information in `cdic` for `dataname`, unless value is `missing`
or `nothing`, which are returned unchanged.  This only handles one
level of arrays.  
"""
convert_to_julia(cdic,dataname::AbstractString,value) = begin
    return convert_to_julia(cdic,find_category(cdic,dataname),find_object(cdic,dataname),value)
end

"""
    real_from_meas(value::String)

Remove optionally attached su from `value` with form `dd(ee)` and return as a `Float64`.
"""
real_from_meas(value::String) = begin
    #println("Getting real value from $value")
    if '(' in value
        #println("NB $(value[1:findfirst(isequal('('),value)])")
        return parse(Float64,value[1:findfirst(isequal('('),value)-1])
    end
    return parse(Float64,value)
end

real_from_meas(value::Missing) = missing

Range(v::String) = begin
    lower,upper = split(v,":")
    parse(Int32,lower),parse(Int32,upper)
end
