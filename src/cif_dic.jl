# CIF Dictionaries

export get_names_in_cat,abstract_cif_dictionary,has_drel_methods
export get_julia_type_name, get_dimensions, convert_to_julia
export get_container_type

abstract type abstract_cif_dictionary end

# Methods that should be instantiated by concrete types

Base.keys(d::abstract_cif_dictionary) = begin
    error("Keys function should be defined for $(typeof(d))")
end

Base.length(d::abstract_cif_dictionary) = begin
    return length(keys(d))
end

has_drel_methods(d::abstract_cif_dictionary) = true

"""
get_names_in_cat(d::abstract_cif_dictionary,catname;aliases=false,only_items=true)

Return a list of all names in `catname`, as defined in `d`. If `aliases`, include any
declared aliases of the name. If `only_items` is false, return child categories as
well.
"""
get_names_in_cat(d::abstract_cif_dictionary,catname;aliases=false,only_items=true) = begin
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


"""Convert to the julia type for a given category, object and String value.
This is clearly insufficient as it only handles one level of arrays.

The value is assumed to be an array containing string values of the particular 
dataname, which is as usually returned by the CIF readers, even for single values.

All functions should return missing and nothing as is.
"""
convert_to_julia(cdic,cat,obj,value::Array) = begin
    julia_base_type,cont_type = get_julia_type_name(cdic,cat,obj)
    if typeof(value) == Array{julia_base_type,1} return value end
    change_func = (x->x)
    #println("Julia type for $cat/$obj is $julia_base_type, converting $value")
    if julia_base_type == Integer
        change_func = (x -> map(y->parse(Int,y),x))
    elseif julia_base_type == Float64
        change_func = (x -> map(y->real_from_meas(y),x))
    elseif julia_base_type == Complex
        change_func = (x -> map(y-> if ismissing(y) || isnothing(y) y else parse(Complex{Float64},y) end,x))   #TODO: SU on values
    elseif julia_base_type in (String,AbstractString)
        change_func = (x -> map(y-> if ismissing(y) || isnothing(y) y else String(y) end,x))
    elseif julia_base_type == Symbol("CaselessString")
        change_func = (x -> map(y-> if ismissing(y) || isnothing(y) y else CaselessString(y) end,x))
    end
    if cont_type == "Single"
        return change_func(value)
    elseif cont_type in ["Array","Matrix"]
        return map(change_func,value)
    else error("Unsupported container type $cont_type")   #we can do nothing
    end
end

convert_to_julia(cdic,dataname::AbstractString,value) = begin
    return convert_to_julia(cdic,find_category(cdic,dataname),find_object(cdic,dataname),value)
end

real_from_meas(value::String) = begin
    #println("Getting real value from $value")
    if '(' in value
        #println("NB $(value[1:findfirst(isequal('('),value)])")
        return parse(Float64,value[1:findfirst(isequal('('),value)-1])
    end
    return parse(Float64,value)
end

Range(v::String) = begin
    lower,upper = split(v,":")
    parse(Number,lower),parse(Number,upper)
end
