# Routines to merge data blocks. Data blocks can only be merged
# if a dictionary is provided that defines Set category keys
# and their children.

export merge_blocks!, merge_block!, merge_loop!

"""
    merge_blocks!(blocks::Cif, dict)

Merge the blocks in `blocks` according to the relational model
defined in `dict`, returning a single CifBlock.
"""
merge_blocks!(blocks::Cif, dict) = begin

    startn, startb = first(blocks)

    for (i, (name, block)) in enumerate(blocks)
        if name == startn continue end
        new_id = "$i-" * (length(name) > 6 ? name[begin:6] : name)
        startb = merge_block!(startb, block, dict, ids = (startn, new_id))
    end

    return startb
end

"""
Merge `addition` into `base`.
"""
merge_block!(base::CifBlock, addition::CifBlock, dict; ids = ("1", "2")) = begin

    # Regularise
    
    make_set_loops!.([base,addition], Ref(dict))

    # Find merging categories

    top_level_cats = [x[1] for x in get_single_key_cats(dict)]
    all_base_cats = map(x-> find_category(dict, x[1]), get_loop_names(base))
    all_add_cats =  map(x-> find_category(dict, x[1]), get_loop_names(addition))

    bc_lookup = Dict(zip(all_base_cats, get_loop_names(base)))
    add_lookup = Dict(zip(all_add_cats, get_loop_names(addition)))
    
    common_cats = intersect(all_base_cats, all_add_cats)
    common_set_cats = filter(x-> is_set_category(dict, x) && x in top_level_cats, common_cats)

    @debug "Merging cats" common_cats
    
    # Check that we have key data names defined

    for csc in common_cats

        @debug "Processing $csc"

        csck = get_keys_for_cat(dict, csc)
        if length(csck) == 0
            @warn "Category $csc: no key data names defined. Values must be identical for successful merge"
        end

        # Only add keys that have no parent data name
        
        filter!(x -> get_ultimate_link(dict, x) == x, csck) 

        @debug "Key data names" csck

        # Get a name to refer to the category

        csc_name = get_loop_names(base, csc, dict)[1]
        add_name = get_loop_names(addition, csc, dict)[1]
        
        # Check for keys and add if necessary

        for k in csck

            # Add keys to base block if necessary
            
            if haskey(base, k) continue end
            if length(base[bc_lookup[csc][1]]) > 1
                throw(error("Category $csc has more than 1 row and no $k value"))
            end

            @debug "Adding $k to base block" ids[1]
            base[k] = [ids[1]]
            add_to_loop!(base, csc_name, k)
                         
            # Add keys to additional block if necessary

            if !haskey(addition, k)
                if length(addition[add_lookup[csc][1]]) > 1
                    throw(error("Category $csc has more than 1 row and no $k value"))
                else

                    newid = ids[2]
                    i = 0
                    while newid in base[k]
                        i = i+1
                        newid = ids[2]*"$i"
                    end

                    @debug "Adding $k to mergee" newid
                    addition[k] = [newid]
                    add_to_loop!(addition, add_name, k)
                end
            end

        end

        for k in csck

            @debug "Adding child keys of $k"

            if length(base[k]) == 1
                add_child_keys!(base, k, dict)
            end

            if length(addition[k]) == 1
                add_child_keys!(addition, k, dict)
            end

        end

    end

    for cc in common_cats

        @debug "Merging loops for" cc
        
        merge_loop!(base, addition, cc, dict)
    end

    # Now add non-common categories from addition

    for loop_group in get_loop_names(addition)
        
        if find_category(dict, loop_group[1]) in common_cats
            continue
        end

        for lg in loop_group
            base[lg] = addition[lg]
        end

        create_loop!(base, loop_group)
    end
end

"""
    merge_loop!(base, addition, catname, dict)

Merge the loop for `catname` from `addition` into the appropriate 
loop in `base` so that `base` conforms to the description 
in `dict`. Any missing key values cause an error
"""
merge_loop!(base, addition, catname, dict) = begin
    
    base_names = get_loop_names(base, catname, dict)
    add_names  = get_loop_names(addition, catname, dict)

    kk = get_keys_for_cat(dict, catname)
    if intersect(kk, base_names) != kk || intersect(kk, add_names) != kk
        @debug "Keys missing" kk base_names add_names
        throw(error("One of keys for $catname missing when merging loop"))
    end

    # Add values for missing names
    
    missing_in_base = setdiff(add_names, base_names)

    for mib in missing_in_base
        @debug "Adding missing values for $mib"
        base[mib] = Vector{Union{Missing, eltype(addition[mib])}}(missing, length(base[base_names[1]]))
        add_to_loop!(base, base_names[1], mib)
    end

    missing_in_add = setdiff(base_names, add_names)

    for mia in missing_in_add
        @debug "Adding missing values for $mia"
        addition[mia] = Vector{Union{Missing, eltype(base[mib])}}(missing, length(addition[add_names[1]]))
        add_to_loop!(addition, add_names[1], mia)
    end

    all_names = union(base_names, add_names)

    # Verify and remove duplicates, merge missing

    have_new = verify_rows!(base, addition, kk, loop_key = all_names[1])

    if have_new
        for cc in all_names
            append!(base[cc],addition[cc])
        end

        create_loop!(base, all_names)
    end
    
end
