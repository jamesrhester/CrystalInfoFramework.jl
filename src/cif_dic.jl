# CIF Dictionaries

export get_names_in_cat,abstract_cif_dictionary

abstract type abstract_cif_dictionary end

# Methods that should be instantiated by concrete types

Base.keys(d::abstract_cif_dictionary) = begin
    error("Keys function should be defined for $(typeof(d))")
end

Base.length(d::abstract_cif_dictionary) = begin
    return length(keys(d))
end

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


