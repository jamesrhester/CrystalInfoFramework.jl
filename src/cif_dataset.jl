# A CifDataset offers a view of a CIF file as a single collection of relational
# tables.
export CifDataset, CifSetProjection
export get_by_signature, has_signature, add_to_cat!, is_allowed_cat
export sieve_block!

"""
   A CifSetProjection looks like a particular type of CifBlock, where all Set-valued
   keys take a single value and are omitted
"""
struct CifSetProjection <: CifContainer
    setkeys::Dict{String, String} #the set keys and values that are projected
    top_cats::Set{String} # The categories corresponding to the keys
    equivalents::Dict{String, Vector{Tuple{String, String}}} #child data names (cat, name)
    cat_lookup::Dict{Union{String, Nothing}, Vector{String}} #names in categories
    values::Dict{String, Vector{Any}} #All the non-set-key values
end

CifSetProjection(sig::Dict, d::AbstractCifDictionary) = begin

    # We only want to handle categories that require all set categories from the
    # sig. This includes the categories from the sig as well.

    top_cats = find_category.(Ref(d), keys(sig))
    equivs = map( x -> (x, get_dataname_children(d, x)), collect(keys(sig)))
    allowed_cats = get_cats_for_sets(d, top_cats)

    @debug "Allowed cats for $sig" equivs allowed_cats
    
    for (k, v) in equivs
        filter!(v) do one_link
            cat = find_category(d, one_link)
            catkeys = get_keys_for_cat(d, cat)
            if !(one_link in catkeys) || !(cat in allowed_cats)

                @debug "Dropping $one_link"
                false
            elseif length(sig) > 1
                !(cat in top_cats)
            else
                @debug "Accepting $one_link"
                true
            end
        end
    end

    if length(first(equivs)[2]) == 0
        @debug "Signature $sig does not refer to any categories"
        return nothing
    end
    
    equivs = [k => map( c -> (find_category(d, c), c) , children) for (k, children) in equivs]

    @debug "Calculated equivalent data names" equivs
    
    equivs = Dict(equivs)
    cl = Dict{Union{String,Nothing}, Vector{String}}(map( x -> (find_category(d, x) => [x]), collect(keys(sig))))
    CifSetProjection(sig, Set(top_cats), equivs, cl, Dict{String, Vector{Any}}())
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

    if catname in c.top_cats return 1 end
    
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

    catname in allowed_categories(cp)
end

allowed_categories(cp::CifSetProjection) = begin
    all_info = Iterators.flatten(values(cp.equivalents))
    (cat for (cat, k) in all_info)
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
get_all_unlooped_names(c::CifSetProjection) = begin
    mostly = setdiff(keys(c.values), Iterators.flatten(get_loop_names(c)))
    Iterators.flatten((mostly, keys(c.setkeys)))
end

get_data_values(c::CifSetProjection) = c.values

get_signature(cp::CifSetProjection) = cp.setkeys
get_dataname_children(cp::CifSetProjection, key) = begin

    if !(key in keys(get_signature(cp)))
        throw(error("Cannot work out children for $key"))
    end

    return (k for (_, k) in cp.equivalents[key])
end

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
    ii = indexin(bad, datanames)
    for one_nasty in ii
        dname = datanames[one_nasty]
        dval = datavalues[one_nasty]
        if get(get_signature(cp), dname, nothing) == dval[] continue end
        throw(error("Changing set key data values not allowed: $dname = $dval"))
    end

    # Now remove equivalent datanames from further consideration

    setdiff!(datanames, bad)
    
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
    add_new_cat!(cp::CifSetProjection, catname, datanames, datavalues)

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
    Add relevant contents of block `c`. Currently will only work if category
    relies on implicit values of Set category keys. Returns true if anything
    was added to the block.

"""
sieve_block!(csp::CifSetProjection, c::CifContainer, d::DDLm_Dictionary) = begin

    keynames = keys(get_signature(csp))
    can_do = all( x -> has_implicit_only(csp, c, x), keynames)
    if !can_do
        throw(error("Unable to sieve block if children of key-valued data names $keynames are present"))
    end

    block_sig = Dict((k => c[k][] for k in keynames))
    if block_sig != get_signature(csp)

        @debug "$block_sig != $(get_signature(csp)), no additions"
        
        return false
    end

    added_sthing = false
    for one_cat in all_categories_in_block(c, d)
        if is_allowed_cat(csp, one_cat)

            @debug "Adding $one_cat"

            # Following gymnastics so that unknown names looped together are included
            
            n = any_name_in_cat(c, one_cat, d)
            all_names = get_loop_names(c, n)
            if length(all_names) == 0
                all_names = get_loop_names(c, one_cat, d)
            end
            
            all_values = [c[n] for n in all_names]
            add_to_cat!(csp, one_cat, all_names, all_values)
            added_sthing = true
        end
    end

    return added_sthing
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
    
    all_sets = get_set_categories(d)
    all_keyed_sets = filter( all_sets ) do x
        k = d.block[:category_key]
        try
            size(k[(master_id = x,)],1) == 1
        catch KeyError
            false
        end
    end
    
    key_data_names = Iterators.flatten(get_keys_for_cat.(Ref(d), all_keyed_sets))

    # List keys that are implicit in this block
    
    implicit_keys = filter( x -> has_implicit_only(cf, d, x), collect(key_data_names))
    all_vals = collect_values.(Ref(cf), Ref(d), key_data_names)
    key_data_names = filter( x -> length(x[2]) > 0, collect(zip(key_data_names, all_vals)))

    all_implicit = length(key_data_names) == length(implicit_keys)

    @debug "Keys with values $key_data_names" implicit_keys all_implicit
    
    # For each combination of keys and values, create a CifSetProjection block

    all_categories = all_categories_in_block(cf, d)
    key_data_names = Dict(key_data_names)
    
    all_key_combos = powerset(collect(keys(key_data_names)), 1)
    proto_dataset = CifDataset(d)

    if !all_implicit
        throw(error("Currently unable to create Dataset from non-implicit blocks"))
    end
    
    for akc in all_key_combos
        all_value_combos = Iterators.product(key_data_names[x][1] for x in akc)
        sig = Dict(zip(akc, (a[1] for a in all_value_combos)))

        csp = CifSetProjection(sig, d)
        if isnothing(csp)

            @debug "$sig rejected"
            continue
        end
        
        @debug "Created signature $sig"

        if sieve_block!(csp, cf, d)
            @debug "Added to block"
            proto_dataset[sig] = csp
        end
    end

    return proto_dataset
end

iterate(c::CifDataset) = iterate(c.blocks)
iterate(c::CifDataset, s) = iterate(c.blocks, s)

haskey(c::CifDataset, sig::Dict) = haskey(c.blocks, sig)

getindex(c::CifDataset, sig::Dict) = c.blocks[sig]
setindex!(c::CifDataset, val::CifSetProjection, sig) = c.blocks[sig] = val

"""
    merge_into_dataset(c::CifDataset, cb::CifContainer)

Add the contents of `cb` to `c`.
"""
merge_into_dataset!(c::CifDataset, cb::CifContainer) = begin

    merge_datasets!(c, CifDataset(cb, c.reference_dict))
end

merge_datasets!(base::CifDataset, new::CifDataset; noverify = true) = begin

    if base.reference_dict != new.reference_dict
        throw(error("Can only combine datasets based on identical dictionaries"))
    end

    for (sig, contents) in new
        if haskey(base, sig)
            continue
        end
        base[sig] = new[sig]
    end
    
end

CifDataset(cf::Cif, d::DDLm_Dictionary) = begin

    base = CifDataset(first(cf).second, d)
    if length(cf) > 1
        for (i, entry) in enumerate(cf)
            if i == 1 continue end

            bname, contents = entry
            @debug "Now merging block $bname"
            merge_into_dataset!(base, contents)
        end
    end

    return base
end

#== Utility routines ==#

"""
    has_implicit_only(c::CifContainer, d::DDLm_Dictionary, keyname)

Returns true if the only values for set-valued keys are implicit, i.e. there are
no child keys of `keyname` in the block. This would be the normal situation for legacy
CIFs. If `keyname` is absent returns false. If more than one value is present,
return false.
"""
has_implicit_only(c::CifContainer, d::DDLm_Dictionary, keyname) = begin

    if !haskey(c, keyname) return false end
    if length(c[keyname]) != 1 || ismissing(c[keyname]) return false end
    
    ch = get_dataname_children(d, keyname)
    filter!( x -> x != keyname && haskey(c, x), ch)
    filter!( x -> x in get_keys_for_cat(d, find_category(d, x)), ch)
    return length(ch) == 0
end

"""
    Use dictionary information in `csp` to deduce implicit key behaviour in `c`.
"""
has_implicit_only(csp::CifSetProjection, c::CifContainer, keyname) = begin

    topkeys = keys(get_signature(csp))
    if !all( x -> haskey(c, x), topkeys) return false end
    if !all( x -> length(c[x]) == 1 || ismissing(c[x]), topkeys) return false end
    dc = get_dataname_children(csp, keyname)
    return all( x -> x == keyname || !haskey(c, x), dc)
end

"""
    collect_values(c::CifContainer, d::DDLm_Dictionary, keyname; keys_only = true)

Get all values for the specified category key, including children. If `keys_only`
is true, ignore values for non-key data names.
"""
collect_values(c::CifContainer, d::DDLm_Dictionary, keyname; keys_only = true) = begin

    child_dns = get_dataname_children(d, keyname)
    if keys_only
        filter!( x -> x in get_keys_for_cat(d, find_category(d, x)), child_dns)
    end
    
    all_vals = []

    for cd in child_dns
        if haskey(c, cd)
            append!(all_vals, c[cd])
        end
    end

    return unique!(all_vals)
end

