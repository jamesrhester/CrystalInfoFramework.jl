# A CifDataset offers a view of a CIF file as a single collection of relational
# tables.
export CifDataset, CifSetProjection
export get_by_signature, has_signature

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
    equivs = map(equivs) do e
        k, children = e
        k => map( c -> (find_category(d, c), c) , children)
    end

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

    if has_category(c, catname)
        n = get_category_names(c, catname)
        return length(c[first(n)])
    else
        return 0
    end
    
end

"""
    get_category_names(c::CifDataset, catname)

Return all data names thought to belong to `catname` in `c`. 
"""
get_category_names(c::CifSetProjection, catname) = begin
    c.cat_lookup[catname]
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

Extend `catname` with the `catcontents`, which is a [names, contents] list
where `contents` are vectors of values. Any names not present in either list
are assigned `missing` values.
"""
add_to_cat!(cp::CifSetProjection, catname, catcontents) = begin
    (names, values) = catcontents
    new_names = setdiff(names, get_category_names(cp, catname))
    missed_names = setdiff(get_category_names(cp, catname), names)
    old_len = length(cp, catname)
    new_len = length(first(values))

    # Align pre-existing lengths

    for nn in new_names
        a = Vector{Any, old_len}[]
        fill!(a, missing)
        cp.values[nn] = a
    end

    # Add new names to lookup
    
    append!(cp.cat_lookup[catname], new_names)


    # Add to existing values

    for on in get_category_names(cp, catname)
        ii = indexin([on], names)[]
        if !isnothing(ii)
            append!(cp.values[on], values[ii])
        else
            # Not supplied with anything
            append!(cp.values[on], fill(missing, new_len))
        end
    end
    
end

"""
    A CifDataset provides a relational view of a collection of Cif blocks
"""
struct CifDataset <: CifContainer
    blocks::Array{CifSetProjection, 1}
    reference_dict::DDLm_Dictionary    
end

CifDataset(cf::CifContainer, d::DDLm_Dictionary) = begin

    # Work out which Set keys are in play
    
    all_categories = get_categories(cf)
    all_sets = get_set_categories(d)
    all_keyed_sets = filter( x -> size(d[x][:category_key], 1) == 1, all_sets)
    key_data_names = Iterators.flatten(get_keys_for_cat.(Ref(d), all_keyed_sets))
    all_vals = collect_values.(Ref(cf), Ref(d), key_data_names)

    # For each combination of keys and values, create a CifSetProject block

    proto_dataset = CifDataset(CifSetProjection[], d)

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

has_signature(c::CifDataset, sig::Dict) = begin
    for v in c
        if get_signature(v) == sig return true
        end
    end
    return false
end

get_by_signature!(c::CifDataset, sig::Dict) = begin
    for v in c
        if get_signature(v) == sig return v end
    end
    csp = CifSetProjection(sig, c.reference_dict)
    push!(c.blocks, csp)
    return csp
end

