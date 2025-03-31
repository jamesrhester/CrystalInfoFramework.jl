# Utility routines for interrogating/updating data blocks based on dictionary information

"""
    has_category(block,catname,dict)

Return `true` if `block` contains data names from `catname`, defined in `dict`.
"""
has_category(block,catname,dict) = begin

    all_names = get_names_in_cat(dict,catname,aliases=true)
    any(x->x in keys(block), all_names)
    
end

"""
    get_loop_names(block, catname, dict)

Return a list of data names from `catname` in `block`, using
`dict` for reference.
"""
get_loop_names(block, catname, dict) = begin

    all_names = get_names_in_cat(dict, catname, aliases = true)
    filter!(x -> x in keys(block), all_names)
    
end

count_rows(block, catname, dict) = begin
    ln = get_loop_names(block, catname, dict)
    if length(ln) == 0 return 0 end
    return length(block[ln[1]])
end

any_name_in_cat(block, catname, dict) = get_loop_names(block, catname, dict)[1]

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

            @debug "Adding value for $an" new_val
            
            if has_category(block, cat, dict)
                cat_name = any_name_in_cat(block, cat, dict) #to refer to category
                num_rows = count_rows(block, cat, dict)
                block[an] = fill(new_val, num_rows)
                add_to_loop!(block, cat_name, an)
            end
        end
    end
end

"""
    make_set_loops(block,dict)

Use information in `dict` to put any single-valued data names in `block` into loops.
"""
make_set_loops!(block,dict) = begin

    all_names = collect(keys(block))

    # Find unlooped by removing looped names

    setdiff!(all_names, get_loop_names(block)...)

    # Collect remainder into loops
    
    while length(all_names) > 0
        nm = pop!(all_names)
        cat = find_category(dict, nm)
        ct_names = get_loop_names(block, cat, dict)

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

        @debug "Common values" common_vals

    else
        
        base_index = add_index = 1

    end

    all_names = get_loop_names(base, length(keynames) > 0 ? keynames[1] : loop_key)

    # Check all entries
    
    for (bi, ai) in zip(base_index, add_index)
        for one_name in all_names
            if base[one_name][bi] != addition[one_name][ai]
                @error "Contradictory values" one_name bi ai base[one_name][bi] addition[one_name][ai]
                throw(error("Contradictory values for $one_name at positions $bi / $ai:"))
            end
        end

        # We can completely drop row ai

        @debug "Found duplicate row for $keynames" bi ai
        
        drop_row!(addition, first(all_names), ai)

    end

    return haskey(addition, first(all_names))
end

"""

"""
