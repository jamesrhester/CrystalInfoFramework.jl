# A CifDataset offers a view of a CIF file as a single collection of relational
# tables.
export CifDataset, CifSetProjection
export get_by_signature, has_signature, add_to_cat!, is_allowed_cat

"""
   A CifSetProjection looks like a particular type of CifBlock, where all Set-valued
   keys take a single value and are omitted
"""
struct CifSetProjection <: CifContainer
    setkeys::Dict{String, String} #the set keys and values that are projected
    equivalents::Dict{String, Vector{Tuple{String, String}}} #child data names (cat, name)
    cat_lookup::Dict{Union{String, Nothing}, Vector{String}} #names in categories
    values::Dict{String, Vector{Any}} #All the non-set-key values
end

CifSetProjection(sig::Dict, d::AbstractCifDictionary) = begin

    equivs = map( x -> (x, get_dataname_children(d, x)), collect(keys(sig)))
    for (k, v) in equivs
        filter!(v) do one_link
            cat = find_category(d, one_link)
            catkeys = get_keys_for_cat(d, cat)
            if !(one_link in catkeys)
                false
            else
                finalkeys = get_ultimate_link.(Ref(d), catkeys)
                finalcats = find_category.(Ref(d), finalkeys)
                count( x->is_set_category(d, x), finalcats) == length(sig) || length(catkeys) == 1 && catkeys[] in keys(sig)
            end
        end
    end
    
    equivs = [k => map( c -> (find_category(d, c), c) , children) for (k, children) in equivs]

    @debug "Calculated equivalent data names" equivs
    
    equivs = Dict(equivs)
    cl = Dict{Union{String,Nothing}, Vector{String}}(map( x -> (find_category(d, x) => [x]), collect(keys(sig))))
    CifSetProjection(sig, equivs, cl, Dict{String, Vector{Any}}())
end

haskey(c::CifSetProjection, k::String) = begin

    k = lowercase(k)
    if haskey(c.values, k) return true end
    if k in keys(c.setkeys) return true end
    for (_, equiv) in c.equivalents
        for (cat, name) in equiv
            if name == k && has_category(c, cat) return true end
        end
        
    end
    return false
        
end

getindex(c::CifSetProjection, k::String) = begin

    k = lowercase(k)
    if k in keys(c.values) return c.values[k] end
    if k in keys(c.setkeys) return [c.setkeys[k]] end
    for (parent, equiv) in c.equivalents
        for (cat, name) in equiv
            if name == k
                return fill(c.setkeys[parent], length(c, cat))
            end
        end
    end

    return missing       

end

keys(c::CifSetProjection) = begin
    all_info = Iterators.flatten(values(c.equivalents))
    equiv_keys = (k for (cat,k) in all_info if has_category(c, cat))
    return Iterators.flatten((keys(c.values), equiv_keys)) 
end

length(c::CifSetProjection, catname) = begin

    topcats = (v[1][1] for (k, v) in c.equivalents)

    if catname in topcats return 1 end
    
    if has_category(c, catname)
        n = get_category_names(c, catname, non_set = true)
        return length(c[first(n)])
    else
        return 0
    end
    
end

"""
   is_allowed(cp::CifSetProjection, catname)

Return true if `catname` is allowed for `cp`.
"""
is_allowed_cat(cp::CifSetProjection, catname) = begin

    all_info = Iterators.flatten(values(cp.equivalents))
    catname in (cat for (cat,k) in all_info)
end

"""
    get_category_names(c::CifDataset, catname; non_set = false)

Return all data names thought to belong to `catname` in `c`. If `non_set` is true,
only return those data names that are not implicitly valued.
"""
get_category_names(c::CifSetProjection, catname; non_set = false) = begin

    all_names = get(c.cat_lookup, catname, [])

    if non_set
        all_names = filter( x-> x in keys(c.values), all_names)
    end

    return all_names
end

has_category(c::CifSetProjection, catname) = catname in keys(c.cat_lookup)

get_loop_names(c::CifSetProjection) = [v for (cat,v) in c.cat_lookup if length(c, cat) > 1]
get_data_values(c::CifSetProjection) = c.values

"""
    Get all values for the specified category key, including children
"""
collect_values(c::CifContainer, d::DDLm_Dictionary, keyname) = begin

    child_dns = get_dataname_children(d, keyname)
    all_vals = []

    for cd in child_dns
        if haskey(c, cd)
            append!(all_vals, c[cd])
        end
    end

    return unique!(all_vals)
end

get_signature(cp::CifSetProjection) = cp.setkeys

"""
    add_to_cat!(cp::CifSetProjection, catname, catcontents)

Extend `catname` with the `datavalues` for each of the `datanames`. If some datanames
are already present, all values are assumed to be additional to the current list and
appended, with missing values in the gaps. If all names are new and the lengths are
identical, they are simply added. If all names are new and lengths are different, an
error is raised as the correct action is unclear.
"""
add_to_cat!(cp::CifSetProjection, catname, datanames, datavalues) = begin

    # Lengths must be the same

    if length(unique!(length.(datavalues))) != 1
        throw(error("Supplied data values for $catname have different lengths"))
    end
    
    if !has_category(cp, catname)
        add_new_cat!(cp, catname, datanames, datavalues)
        return
    end

    # Values of set and equivalent keys may not change
    
    all_info = Iterators.flatten(values(cp.equivalents))
    equiv_keys = (k for (_,k) in all_info)
    bad = intersect(datanames, equiv_keys)
    if length(bad) > 0
        throw(error("Changing set key data values not allowed: $bad"))
    end
    
    # Work out overlap of names and lengths
    
    new_names = setdiff(datanames, get_category_names(cp, catname, non_set = true))
    missed_names = setdiff(get_category_names(cp, catname, non_set = true), datanames)
    old_len = length(cp, catname)
    new_len = length(first(datavalues))

    # Make sure we have a recognisable situation

    if length(new_names) == length(datanames) && old_len != new_len
        throw(error("Ambiguous task: names all new but lengths don't match pre-existing names"))
    end
    
    # If adding to top cats, enforce single value

    topcats = (k[1][1] for (k, v) in cp.equivalents)

    if catname in topcats && new_len != 1

        @debug "Non length 1 addition to $catname" datanames datavalues
        throw(error("Additions to Set category $catname may only be length 1"))
    end
    
    # Align pre-existing lengths if some names common

    if length(new_names) != length(datanames) 
        for nn in new_names
            a = Vector{Any}(missing, old_len)
            cp.values[nn] = a
        end
    end
    
    # Add new names to lookup
    
    append!(cp.cat_lookup[catname], new_names)

    if length(new_names) == length(datanames)
        for (i,nn) in enumerate(new_names)
            cp.values[nn] = datavalues[i]
        end

    else
        
        # Add to existing values

        for on in get_category_names(cp, catname, non_set = true)

            @debug "Adding to $on"
            
            ii = indexin([on], datanames)[]
            if !isnothing(ii)
                append!(cp.values[on], datavalues[ii])
            else
                # Not supplied with anything
                @debug "Filling out $on with missing values"
                append!(cp.values[on], fill(missing, new_len))
            end
        end
    end
end

add_to_cat!(cp::CifSetProjection, ::Nothing, datanames, datavalues) = begin

    if length(cp.setkeys) != 0
        throw(error("$(cp.setkeys) is not compatible with unknown category for $datanames"))
    end
    
    # All data values must be length 1

    if any( x->length(x) != 1, datavalues)
        throw(error("Nothing category holds only length-1 data values"))
    end

    new_names = setdiff(datanames, get_category_names(cp, nothing))
    append!(cp.cat_lookup, new_names)
    for (i,dn) in enumerate(datanames)
        cp.values[dn] = datavalues[i]
    end
    
end


"""
    Add category `catname` to `cp`. `datavalues` contains the values in the
    same order as `datanames`. This should not be called directly. If `catname`
    already exists, an error is thrown.
"""
add_new_cat!(cp::CifSetProjection, catname, datanames, datavalues) = begin

    if has_category(cp, catname)
        throw(error("$catname already exists"))
    end

    if !(is_allowed_cat(cp, catname))
        throw(error("$catname is not appropriate for $(cp.setkeys)"))
    end
    
    cp.cat_lookup[catname] = datanames
    for (n, v) in zip(datanames, datavalues)
        cp.values[n] = v
    end
    
end

"""
    A CifDataset provides a relational view of a collection of Cif blocks
"""
struct CifDataset <: CifContainer
    blocks::Dict{Dict{String, String}, CifSetProjection}
    reference_dict::DDLm_Dictionary
end

CifDataset(d::DDLm_Dictionary) = CifDataset(Dict{Dict{String, String}, CifSetProjection}(), d)

CifDataset(cf::CifContainer, d::DDLm_Dictionary) = begin

    # Work out which Set keys are in play
    
    all_categories = get_categories(cf)
    all_sets = get_set_categories(d)
    all_keyed_sets = filter( x -> size(d[x][:category_key], 1) == 1, all_sets)
    key_data_names = Iterators.flatten(get_keys_for_cat.(Ref(d), all_keyed_sets))
    all_vals = collect_values.(Ref(cf), Ref(d), key_data_names)

    # For each combination of keys and values, create a CifSetProjection block

    proto_dataset = CifDataset(d)

    for one_cat in all_categories
        ak = get_keys_for_cat(d, one_cat)
        set_rel = get_ultimate_link.(Ref(d), ak)
        key_loc = indexin(set_rel, key_data_names)
        all_vals = map(1:length(ak)) do kl
            if key_loc[kl] != nothing
                (key_data_names[key_loc[kl]], unique(cf[ak[kl]]))
            end
        end

        # all vals is now list of (set key, all vals) tuples

        child_set_keys = (first(x) for x in all_vals)
        all_poss_vals = (second(x) for x in all_vals)
        for combo in Iterators.product(all_poss_vals...)
            
            sig = Dict{String, Vector{String}}(collect(zip(child_set_keys, combo)))
            new_cat = filter_on_values(cf, one_cat, sig)
            if isnothing(new_cat) continue end
            
            csp = get_by_signature!(proto_dataset, sig)
            add_to_cat!(csp, one_cat, new_cat) 
        end
    end
end

iterate(c::CifDataset) = iterate(c.blocks)
iterate(c::CifDataset, s) = iterate(c.blocks, s)

haskey(c::CifDataset, sig::Dict) = haskey(c.blocks, sig)

getindex(c::CifDataset, sig::Dict) = c.blocks[sig]
setindex!(c::CifDataset, val::CifSetProjection, sig) = c.blocks[sig] = val
