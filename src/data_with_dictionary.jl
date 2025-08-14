
"""
    Guess the category that `dname` belongs to.
"""
guess_category(dname::String, c::CifContainer, d::AbstractCifDictionary) = begin

    fc = find_category(d, dname)
    if !isnothing(fc) return fc end
    
    ln = get_loop_names(c, dname)
    if length(ln) == 0 return nothing end
    guess_category(d, ln)
    
end

"""
   Guess the category looped datanames belong to based on friends in
   the same loop. Useful when non-dictionary data names are included
   in a loop. If a category is merged, choose the closest common parent
   in the hierarchy that exists in the loop.
"""
guess_category(d::DDLm_Dictionary, loopnames) = begin

    current_parent = nothing   #for tracking joinable categories
    for l in loopnames
        fc = find_category(d, l)
        if isnothing(fc) continue
        elseif !is_joinable_category(d, fc) return fc
        else
            current_parent = closest_common_parent(d, current_parent, fc)
        end
        
    end

    return current_parent

end

# Utility routines for interrogating/updating data blocks based on dictionary information
# We should be aware that some non-dictionary-defined data names may be present.

"""
    make_canonical!(d::DDLm_Dictionary, cb::CifContainer)

Change data names in `cb` to unaliased form
"""
make_canonical!(d::DDLm_Dictionary, cb::CifContainer) = begin

    old_names = keys(cb)

    # Set up new names
    
    for on in old_names
        nn = on
        try
            nn = find_name(d, on)
        catch KeyError
            continue
        end
        
        if nn == on continue end
        rename!(cb, on, nn)
    end

end

"""
    make_canonical!(d::DDLm_Dictionary, cf::Cif)

Change data names in `cf` to unaliased form
"""
make_canonical!(d::DDLm_Dictionary, cf::Cif) = begin

    for (k,v) in cf
        make_canonical!(d, v)
    end
    
end

"""
    has_category(block,catname,dict)

Return `true` if `block` contains data names from `catname`, defined in `dict`.
"""
has_category(block, catname, dict) = begin

    all_names = get_names_in_cat(dict,catname,aliases=true)
    any(x->x in keys(block), all_names)
    
end
"""
    all_categories_in_block(block, dict)

Return a list of all categories in the block. Where a loop does not
contain any data names belonging to a known category, a data name
from that loop is returned instead. Where an unlooped data name is
not found, it is assigned category `nothing`.
"""
all_categories_in_block(block, dict) = begin

    cat_list = Union{String, Nothing}[]
    
    # First do looped names

    for l in get_loop_names(block)
        gc = guess_category(dict, l)
        if isnothing(gc)
            push!(cat_list, first(l))  #flag unknown with dataname
        else
            push!(cat_list, gc)
        end
        
    end

    for n in get_all_unlooped_names(block)
        push!(cat_list, find_category(dict, n))
    end

    unique!(cat_list)
end

"""
    get_loop_names(block, catname, dict; children = false)

Return a list of looped data names from `catname` in `block`, using
`dict` for reference. If `children` is `true`, include data
names from child categories. If `even_single` is true, one-item
loops (which could be presented unlooped) are counted as looped.
"""
get_loop_names(block, catname, dict; children = false, even_single = false) = begin

    min_length = even_single ? 0 : 1
    all_names = get_names_in_cat(dict, catname, aliases = true)
    if children
        for c in get_child_categories(dict, catname)
            append!(all_names, get_names_in_cat(dict, c))
        end
    end
    
    filter!(x -> x in keys(block) && length(block[x]) > min_length, all_names)
    
end

get_loop_names(block, ::Nothing, dict; kwargs...) = String[]

count_rows(block, catname, dict) = begin
    ln = get_loop_names(block, catname, dict, even_single = true)
    if length(ln) == 0 return 0 end
    return length(block[ln[1]])
end

any_name_in_cat(block, catname, dict) = begin

    all_names = get_names_in_cat(dict, catname, aliases = true)
    x = findfirst( x -> x in keys(block), all_names)
    return all_names[x]
end

"""
    get_names_in_cat(block::CifContainer, catname, dict::AbstractCifDictionary)

Return only those names from `catname` that appear in `block`.
"""
get_names_in_cat(block::CifContainer, catname, dict::AbstractCifDictionary) = begin
    all_names = get_names_in_cat(dict, catname, aliases = true)
    all_names = unique(lowercase.(all_names))
    filter!( x -> haskey(block, x), all_names)
end

any_name_in_cat(block, ::Nothing, dict) = begin

    # "nothing" category includes any data name that isn't in a dictionary and
    # can't be guessed from neighbours in a loop

    for n in get_all_unlooped_names(block)
        if find_category(dict, n) == nothing
            return n
        end
    end

    for l in get_loop_names(block)
        gc = guess_category(dict, l)
        if isnothing(gc)
            return first(l)
        end
    end

    return nothing
end

"""
    get_dropped_keys(block, catname, dict)

Return a list of key data names that are dropped in `catname` in `block`
as determined by `dict`.
"""
get_dropped_keys(block, catname, dict) = begin

    dropped_keys = []
    
    # Get the ultimate parent data names
    
    all_keys = get_keys_for_cat(dict, catname)

    for ak in all_keys
        ultimate = get_ultimate_link(dict, ak)

        if !haskey(block, ak)
            push!(dropped_keys, ak)
        end
    end

    return dropped_keys
    
end

"""
    add_dropped_keys!(block, catname, dict)

Add back any key data names that have been dropped due to being
unambiguous. The ultimate parent values must already be present.
"""
add_dropped_keys!(block, catname, dict) = begin

    if !has_category(block, catname, dict)
        return
    end

    keylist = get_dropped_keys(block, catname, dict)
    ultimates = get_ultimate_link.(Ref(dict), keylist)

    @debug "Ultimate keys for $catname" ultimates
    
    for (u,k) in zip(ultimates, keylist)
        if !haskey(block, u)
            @warn "Dropped key is missing, can't update children" u
            continue
        end

        have_names = get_loop_names(block, catname, dict)
        l = length(block[have_names[1]])
        new_vals = fill(block[u],l)

        block[k] = new_vals
        add_to_loop!(block, have_names[1], k)

        @debug "Added $k with value $(new_vals[1]) to category $catname"
    end
        
end

"""
    add_child_keys!(block, k, dict)

Add all child keys of `k` to `block` if missing. The value to use for the
key will be `block[k]`, which must have a single, unique value. Non-key
child data names are *not* added if missing.
"""
add_child_keys!(block, k, dict) = begin

    if length(unique(block[k])) != 1
        throw(error("No unique value for $k available"))
    end

    new_val = unique(block[k])[]
    
    all_names = get_dataname_children(dict, k)

    for an in all_names

        cat = find_category(dict, an)

        # an must be a key data name

        if !(an in get_keys_for_cat(dict, cat))
            continue
        end

        if haskey(block, an)
            
            # Make sure an is consistent if present
            
            if length(unique(block[an])) == 1 && block[an][1] == new_val
                continue
            end
            
            @error "Contradictory values for $an: should be $new_val, found $(block[an][1])"

        else

            # Fill in the values

            if has_category(block, cat, dict)

                @debug "Adding value for $an" new_val
            
                cat_name = any_name_in_cat(block, cat, dict) #to refer to category
                num_rows = count_rows(block, cat, dict)
                block[an] = fill(new_val, num_rows)
                add_to_loop!(block, cat_name, an)
            end
        end
    end
end

"""
    make_set_loops!(block,dict)

Use information in `dict` to put any single-valued data names in `block` into loops.
"""
make_set_loops!(block,dict) = begin

    all_names = get_all_unlooped_names(block)

    # Collect remainder into loops
    
    while length(all_names) > 0
        nm = pop!(all_names)
        cat = find_category(dict, nm)
        if isnothing(cat) continue end
        ct_names = get_names_in_cat(block, cat, dict)

        @debug "Creating loop" ct_names
        
        create_loop!(block, ct_names)
        setdiff!(all_names, ct_names)
    end
end

""" 
    verify_rows!(base, addition, keynames)

Check that there are no rows in `addition` that contradict
anything in `base` for joint values of `keynames`. If identical keys
lead to identical rows, remove. It is assumed that each of the blocks
are already consistent.

If `keynames` is empty, use `loop_key` to access the loop.

The loops should have the same data names defined.
TODO: caseless compare
"""
verify_rows!(base, addition, keynames; loop_key = "") = begin

    # Sanity check

    if length(keynames) == 0 && length(base[loop_key]) > 1
        @error "Cannot merge category with no key data names, containing $loop_key and length > 1"
        throw(error("Cannot merge category with no key data names, containing $loop_key and length > 1 ($(base[loop_key]))"))
    end
    
    if length(keynames) > 0

        base_key_vals = collect(zip(getindex.(Ref(base), keynames)...))
        add_key_vals = collect(zip(getindex.(Ref(addition), keynames)...))

        @debug "Key values to check" keynames base_key_vals add_key_vals
    
        if isdisjoint(base_key_vals, add_key_vals)
            return true
        end

        common_vals = intersect(base_key_vals, add_key_vals)
        base_index = indexin(common_vals, base_key_vals)
        add_index = indexin(common_vals, add_key_vals)

        @debug "Common values" common_vals base_index add_index

    else
        
        base_index = add_index = [1]

    end

    all_base_names = get_loop_names(base, length(keynames) > 0 ? keynames[1] : loop_key)
    all_add_names = get_loop_names(addition, length(keynames) > 0 ? keynames[1] : loop_key)
    
    # Check all entries

    have_missing = false
    rows_to_ignore = []
    for (bi, ai) in zip(base_index, add_index)
        for one_name in all_base_names

            @debug "Checking $bi, $ai for $one_name" addition[one_name][ai] base[one_name][bi]
            if !ismissing(addition[one_name][ai]) && !ismissing(base[one_name][ai])
                if base[one_name][bi] != addition[one_name][ai]
                    @error "Contradictory values" one_name bi ai base[one_name][bi] addition[one_name][ai]
                    throw(error("Contradictory values for $one_name at positions $bi / $ai:"))
                end
            else

                # merge in missing values
                if ismissing(base[one_name][ai])
                    @debug "Assigning to missing" typeof(base[one_name])
                    base[one_name][ai] = addition[one_name][ai]
                end
            end
            
        end

        # We can completely drop row ai

        push!(rows_to_ignore, ai)
    end

    sort!(rows_to_ignore, rev = true)

    @debug "Dropping rows" rows_to_ignore
    
    for r in rows_to_ignore
        drop_row!(addition, first(all_add_names), r)
    end
    
    return haskey(addition, first(all_base_names))
end

"""

"""
