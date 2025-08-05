# A CifDataset offers a view of a CIF file as a single collection of relational
# tables.
export CifDataset, CifSetProjection
export get_by_signature, has_signature, add_to_cat!, is_allowed_cat
export sieve_block!, confirm_all_present, find_mismatches

"""
   A CifSetProjection looks like a particular type of CifBlock, where all Set-valued
   keys take a single value and are omitted
"""
struct CifSetProjection <: CifContainer
    setkeys::Dict{String, String} #the set keys and values that are projected
    top_cats::Set{String} # The categories corresponding to the keys
    equivalents::Dict{String, Dict{String, String}} #child data names (cat => name)
    cat_lookup::Dict{Union{String, Nothing}, Vector{String}} #names in categories
    key_lookup::Dict{String, Vector{String}} #non-set keys for categories
    values::Dict{String, Vector{Any}} #All the non-set-key values
    allowed_categories::Vector{Union{String,Nothing}} #Useful for non-set-related categories
end

CifSetProjection(sig::Dict, d::AbstractCifDictionary) = begin

    # We only want to handle categories that require all set categories from the
    # sig. This includes the categories from the sig as well.

    top_cats = find_category.(Ref(d), keys(sig))
    equivs = map( x -> (x, get_dataname_children(d, x)), collect(keys(sig)))
    allowed_cats = Vector{Union{String, Nothing}}(get_cats_for_sets(d, top_cats))

    @debug "Allowed cats for $sig" equivs allowed_cats

    # Filter out equivalents from non-allowed categories
    
    for (k, v) in equivs
        filter!(v) do one_link
            cat = find_category(d, one_link)
            catkeys = get_keys_for_cat(d, cat)
            if !(one_link in catkeys) || !(cat in allowed_cats)

                # Not a key data name or not an allowed category
                
                @debug "Dropping $one_link"
                false
            elseif length(sig) > 1

                # Only allow top categories to be included
                !(cat in top_cats)
            else
                @debug "Accepting $one_link"
                true
            end
        end
    end

    if any( x -> length(x[2]) == 0, equivs)

        # There must be at least one non-top category that is referred to
        
        @debug "Signature $sig does not refer to any categories"
        return nothing
    end

    # Add in category information
    
    equivs = [k => Dict(map( c -> (find_category(d, c), c) , children)) for (k, children) in equivs]

    @debug "Calculated equivalent data names" equivs
    
    equivs = Dict(equivs)
    
    cl = Dict{Union{String,Nothing}, Vector{String}}(map( x -> (find_category(d, x) => [x]), collect(keys(sig))))

    # Store non-set keys for categories for quick lookup

    non_set_keys = Dict(map( c -> (c => get_non_set_keys_for_cat(d, c)), allowed_cats))
    
    # Include "nothing" as category for empty signature
    if length(sig) == 0
        push!(allowed_cats, nothing)
    end

    CifSetProjection(sig, Set(top_cats), equivs, cl, non_set_keys, Dict{String, Vector{Any}}(), allowed_cats)
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

allowed_categories(cp::CifSetProjection) = cp.allowed_categories
get_categories(cp::CifSetProjection) = keys(cp.cat_lookup)

"""
    get_category_names(c::CifDataset, catname; non_set = false)

Return all data names thought to belong to `catname` in `c`. If `non_set` is true,
only return those data names that are not implicitly valued.
"""
get_category_names(c::CifSetProjection, catname; non_set = false) = begin

    all_names = get(c.cat_lookup, catname, String[])

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

Extend `catname` with the `datavalues` for each of the `datanames`. Key data name
values are used to match rows.
"""
add_to_cat!(cp::CifSetProjection, catname, datanames, datavalues) = begin

    # Lengths must be the same

    if length(unique!(length.(datavalues))) != 1
        throw(error("Supplied data values for $catname have different lengths"))
    end
    
    if !has_category(cp, catname)
        @debug "Adding new category $catname"
        add_new_cat!(cp, catname, datanames, datavalues)
        return
    end

    # Values of set and equivalent keys may not change
    badpos = []  #remember for later deletion
    for (sk, equivs) in cp.equivalents
        ii = indexin([get(equivs, catname, "")], datanames)[]
        if !isnothing(ii)
            push!(badpos, ii)
            dname = datanames[ii]
            dval = datavalues[ii]
            if get(get_signature(cp), dname, nothing) == dval[] continue end
            throw(error("Changing set key data values not allowed: $dname = $dval"))
        end
    end
    
    # Now remove equivalent datanames from further consideration
    # Delete from high to low so that indices don't change
    
    sort!(badpos, rev = true)
    for i in badpos
        @debug "Not proceeding with $(datanames[i])"
        deleteat!(datavalues, i)
        deleteat!(datanames, i)
    end

    if length(datanames) == 0 return end

    # Check that we have key data names

    new_key_dns = indexin(cp.key_lookup[catname], datanames)
    if nothing in new_key_dns
        @error "Missing key data names" cp.key_lookup[catname] datanames new_key_dns
        throw(error("Missing key data names for adding to category $catname"))
    end
    
    # Work out overlap of names and lengths
    
    new_names = setdiff(datanames, get_category_names(cp, catname, non_set = true))
    missed_names = setdiff(get_category_names(cp, catname, non_set = true), datanames)
    common_names = intersect(get_category_names(cp, catname, non_set = true), datanames)
    old_len = length(cp, catname)
    new_len = length(first(datavalues))

    # If category with no non-set keys, enforce single value

    if length(cp.key_lookup[catname]) == 0 && new_len != 1

        @debug "Non length 1 addition to $catname" datanames datavalues
        throw(error("Additions to Set category $catname may only be length 1"))
    end

    # Add dummy values for existing rows if some names common (ie at least key data names)
    
    for nn in new_names
        @debug "Adding empty values for new columns" old_len new_names
        a = Vector{Any}(missing, old_len)
        cp.values[nn] = a
    end

    # Add new names to lookup
    
    append!(cp.cat_lookup[catname], new_names)

    # Cycle through key values, adding/checking

    if length(cp.key_lookup[catname]) > 0
        key_tuples = collect(zip((cp[k] for k in cp.key_lookup[catname])...))
        new_tuples = collect(zip((datavalues[x] for x in new_key_dns)...))
        row_indices = indexin(key_tuples, new_tuples) #lookup existing in new
    else
        row_indices = [1]
    end
    
    new_val_lookup = Dict(zip(datanames, datavalues))
    
    for ri in 1:length(row_indices)
        if isnothing(row_indices[ri])   #not supplied
            continue
        end

        # Check existing values are correct
        for dn in common_names
            if cp.values[dn][ri] != new_val_lookup[dn][row_indices[ri]]
                @debug "Mismatch" cp.values[dn][ri] new_val_lookup[dn][row_indices][ri]
                throw(error("Mismatched values for $dn for row $ri"))
            end
        end

        # Add missing data names
        for dn in new_names
            cp.values[dn][ri] = new_val_lookup[dn][row_indices[ri]]
        end
    end
    
    # Now add any new rows. There cannot be new rows for single-row categories
    if length(cp.key_lookup[catname]) > 0
        row_indices = indexin(new_tuples, key_tuples) #find new key values
    else
        row_indices = []
    end
    
    for ri in 1:length(row_indices)
        if !isnothing(row_indices[ri])   #already handled
            continue
        end

        for dn in datanames
            push!(cp.values[dn], new_val_lookup[dn][ri])
        end

        for dn in missed_names
            push!(cp.values[dn], missing)
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

    @debug "New names for nothing" new_names

    if haskey(cp.cat_lookup,nothing)
        append!(cp.cat_lookup[nothing], new_names)
    else
        cp.cat_lookup[nothing] = new_names
    end

    # If these names are present already, and not identical, then
    # we are unable to include both in the dataset as they contradict
    # one another.

    for (i,dn) in enumerate(datanames)
        if haskey(cp.values, dn)
            if cp.values[dn] != datavalues[i]
                throw(error("Contradictory values for $dn: $(cp.values[dn]) and $(datavalues[i]). Both cannot belong to the same dataset"))
            else
                continue
            end
        else
            cp.values[dn] = datavalues[i]
        end
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
        @debug "Setting $n to $v"
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

            @debug "All looped names for $one_cat" all_names

            if length(all_names) > 0
                all_values = [c[n] for n in all_names]
                add_to_cat!(csp, one_cat, all_names, all_values)
                added_sthing = true
            end

            # Now get unlooped names

            all_names = collect(get_all_unlooped_names(c))
            filter!( x -> find_category(d, x) == one_cat, all_names)
            if length(all_names) == 0 continue end

            @debug "All unlooped names for $one_cat" all_names

            all_values = [c[n] for n in all_names]
            add_to_cat!(csp, one_cat, all_names, all_values)
            added_sthing = true
        end
    end

    return added_sthing
end

"""
    validate_set_values(csp::CifSetProjection, one_cat::String, names, values, d::DDLm_Dictionary)

Confirm that the provided values would not create multiple values for a Set category that has no
keys.
"""
validate_set_values(csp::CifSetProjection, one_cat::String, names, values, d::DDLm_Dictionary) = begin

    # Require that lengths must be one and all values must match current values
    if any( x-> length(x) != 1, values)
        @debug "Non length 1 addition to category $one_cat" names values
        throw(error("Set category $one_cat may only have a single value for the whole dataset"))
    end

    for (n, v) in zip(names, values)
        if haskey(csp, n) && csp[n] != v
            @warn "Value for $n doesn't match: was $(csp[n]), supplied $v"
            throw(error("Value for $n doesn't match: was $(csp[n]), supplied $v"))
        end
    end
    
end

            # Bail if we are adding to a non-keyed Set category which already has values


"""
    A CifDataset provides a relational view of a collection of Cif blocks
"""
struct CifDataset <: CifCollection
    blocks::Dict{Dict{String, String}, CifSetProjection}
    reference_dict::DDLm_Dictionary
end

CifDataset(d::DDLm_Dictionary) = CifDataset(Dict{Dict{String, String}, CifSetProjection}(), d)

CifDataset(cf::CifContainer, d::DDLm_Dictionary) = begin

    key_data_names = get_implicits_for_block(cf, d)
    
    # For each combination of keys and values, create a CifSetProjection block

    all_categories = all_categories_in_block(cf, d)
    key_data_names = Dict(key_data_names)
    
    all_key_combos = powerset(collect(keys(key_data_names)), 1)
    proto_dataset = CifDataset(d)
    
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

    # and do the nothing block!
    csp = CifSetProjection(Dict(), d)
    if !isnothing(csp)
        @debug "Adding nothing block"
        if sieve_block!(csp, cf, d)
            proto_dataset[Dict()] = csp
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
        if !haskey(base, sig)

            base[sig] = new[sig]
            continue
        end
        if sig != Dict()

            if length(base[sig].values) == 0
                base[sig] = new[sig]
            elseif length(new[sig].values) == 0
                continue
            else
                @warn "Old, new blocks for $sig have content, skipping" length(base[sig].values) length(new[sig].values)
            end
 
        end

        # The nothing Set categories have not changed between blocks
        
        d = base.reference_dict # for convenience
        
        for one_cat in get_categories(base[sig])
            all_names = get_category_names(new[sig], one_cat, non_set = true)   
            if length(all_names) == 0 continue end
            
            new_vals = [new[sig][n] for n in all_names]
            add_to_cat!(base[sig], one_cat, all_names, new_vals)            
        end
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

# Debug block contents
_block_census(c::CifDataset) = begin
    outstring = IOBuffer()
    for (sig, contents) in c.blocks
        write(outstring, "$sig $(length(contents.values))\n")
    end
    print(String(take!(outstring)))
end

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

"""
    get_implicits_for_block(cc::CifContainer, d::DDLm_Dictionary)

Return (key, value) tuples for keys with implicit values in `cc`. If child data names
are present, raise an error.
"""
get_implicits_for_block(cc::CifContainer, d::DDLm_Dictionary) = begin

    # Work out which Set keys are in play
    
    all_keyed_sets = get_keyed_set_categories(d)
    key_data_names = Iterators.flatten(get_keys_for_cat.(Ref(d), all_keyed_sets))

    # List keys that are implicit in this block
    
    implicit_keys = filter( x -> has_implicit_only(cc, d, x), collect(key_data_names))
    all_vals = collect_values.(Ref(cc), Ref(d), key_data_names)
    key_data_names = filter( x -> length(x[2]) > 0, collect(zip(key_data_names, all_vals)))

    all_implicit = length(key_data_names) == length(implicit_keys)

    @debug "Keys with values $key_data_names" implicit_keys all_implicit

    if !all_implicit
        throw(error("Block has child data names of Set data names, too complicated."))
    end

    return key_data_names
end

"""
    find_mismatches(cc::CifContainer, cd::CifDataset, dict::DDLm_Dictionary)

Find mismatching data values.
"""
find_mismatches(cc::CifContainer, cd::CifDataset, d::DDLm_Dictionary) = begin

    results_dict = Dict{String, String}()
    key_data_names = Dict(get_implicits_for_block(cc, d))
    for dn in keys(cc)

        @debug "Checking $dn"
        cat = guess_category(dn, cc, d)
        sc = get_set_cats_for_cat(d, cat)

        # Work out block signature for CifDataset
        
        sk = map( x -> get_keys_for_cat(d, x)[], sc)
        want_sig = Dict( x => key_data_names[x][] for x in sk)
        target_block = cd.blocks[want_sig]

        if ismissing(target_block[dn])
            @debug "$dn is missing"
            results_dict[dn] = "Missing"
            continue
        end
        
        if length(cc[dn]) != length(target_block[dn])
            @debug "Lengths don't match for $dn, category $cat, in $want_sig"
            results_dict[dn] = "Lengths don't match for category $cat, in $want_sig"
            continue
        end
        
        # Get any other keys

        non_set_keys = filter( x -> !(get_ultimate_link(d, x) in sk), get_keys_for_cat(d, cat))

        @debug "For $dn in category $cat" want_sig non_set_keys

        # Now check values

        if length(non_set_keys) == 0   #simple value
            if !haskey(target_block, dn) || target_block[dn] != cc[dn]
                @debug "Non-matched value for $dn" target_block[dn] cc[dn]
                results_dict[dn] = "Non-matched value: $(target_block[dn]) $(cc[dn])"
                continue
            else
                @debug "$dn all values found"
                continue
            end
        end

        # Allow for joined categories as best we can by finding equivalent key data names
        # that are present
        
        non_set_keys = map(non_set_keys) do nsk
            real_key = nsk
            while !(haskey(cc, real_key))
                new_key = get_linked_name(d, real_key)

                @debug "$real_key missing, what about $new_key?"
                if new_key == real_key
                    @debug "Failed to find any equivalents of $nsk"
                    return nsk   #fail
                end
                real_key = new_key
            end
            real_key
        end

        @debug "Non-set keys are now $non_set_keys"
        
        # Check looped values sorting on key data name
        # Being generous if all key data names are missing but there's only one line

        generous = length(target_block[dn]) == 1 && all( x -> !haskey(cc, x), non_set_keys)
        if !generous
            key_vals = zip((cc[x] for x in non_set_keys)...)
            target_key_vals = collect(zip((target_block[x] for x in non_set_keys)...))
            positions = indexin(key_vals, target_key_vals)
        else
            positions = [1]
        end
        
        bad = findfirst( x -> cc[dn][x] != target_block[dn][positions[x]], 1:length(cc[dn]))
        if !isnothing(bad)
            @debug "Found mismatching value for $dn at position $bad" cc[dn][bad] target_block[dn][positions[bad]]
            results_dict[dn] = "Found mismatching value at position $bad: $(cc[dn][bad]) $(target_block[dn][positions[bad]])"
            continue
        end

        @debug "$dn all values found in correct order"
    end

    return results_dict
end

confirm_all_present(cf::Cif, cd::CifDataset, d::DDLm_Dictionary) = begin
    for (bn, bv) in cf
        @debug "==== Processing $bn ===="
        if !confirm_all_present( bv, cd , d)
            @debug "Incorrect value found when checking $bn"
            return false
        end
    end
    return true
end

"""
    confirm_all_present(cc::CifContainer, cd::CifDataset, dict::DDLm_Dictionary)

Confirm all items in `cc` are present somewhere in `cd` with correct values.
"""
confirm_all_present(cc::CifContainer, cd::CifDataset, d::DDLm_Dictionary) = begin
    rd = find_mismatches(cc, cd, d)
    return length(rd) == 0
end
