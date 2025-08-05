
"""
    A CifDataBlock holds data that have been described by a CIF dictionary, offering
    efficient per-category access to data.
"""
struct DataDictBlock <: CifContainer
    underlying::Block
    cat_lookup::Dict{Union{String, Nothing}, Vector{String}}
    reference_dict::DDLm_Dictionary   # when new names are added
end

DataDictBlock(c::CifContainer, d::AbstractCifDictionary) = begin

    # We carry out routine operations during construction that would otherwise be performed for every
    # category-based lookup

    ac = all_categories_in_block(c, d)
    cat_lookup = Dict{Union{String, Nothing}, Vector{String}}()
    found_names = []
    cat_lookup[nothing] = []
    
    for one_cat in ac
        names_in_cat = get_loop_names(c, one_cat, d)
        append!(found_names, names_in_cat)
        cat_lookup[one_cat] = names_in_cat
    end

    # Now handle unknowns

    unknown_cat = setdiff(collect(keys(c)), found_names)

    @debug "Have $(length(unknown_cat)) data names without categories" unknown_cat
    
    for uc in unknown_cat
        g = guess_category(uc, c, d)
        push!(cat_lookup[g], uc)
    end

    DataDictBlock(c, cat_lookup, d)
end

Cif{DataDictBlock}(c::Cif, d::AbstractCifDictionary) = begin

    new_contents = Dict{String, DataDictBlock}()
    for b in keys(c)
        new_contents[b] = DataDictBlock(c[b], d)
    end
    
    Cif(new_contents, c.original_file, c.header_comments)
end

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

guess_category(dname::String, c::DataDictBlock) = begin
    guess_category(dname, c, c.reference_dict)
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

# Standard methods for CifContainers

get_loop_names(c::DataDictBlock) = get_loop_names(c.underlying)
get_data_values(c::DataDictBlock) = get_data_values(c.underlying)

setindex!(c::DataDictBlock, v, s) = begin

    s = lowercase(s)
    need_to_update = !haskey(c, s)
    c.underlying[s] = v
    if need_to_update
        cat = guess_category(s, c)
        push!(c.cat_lookup[cat], s)
    end
end

delete!(b::DataDictBlock, name) = begin

    name = lowercase(name)
    old_cat = guess_category(name, b)
    delete!(b.underlying, name)
    b.cat_lookup[old_cat] = filter( x-> x != name, b.cat_lookup[old_cat])
    if length(b.cat_lookup[old_cat]) == 0
        delete!(b.cat_lookup, old_cat)
    end
    
end

rename!(b::DataDictBlock, old, new) = begin

    old = lowercase(old)
    cat = guess_category(old, b)
    
    new = lowercase(new)

    rename!(b.underlying, old, new)
    idx = indexin([old], b.cat_lookup[cat])[]
    if isnothing(idx)
        throw(error("Missing dataname $old in list of names for $cat when renaming to $new"))
    end

    b.cat_lookup[cat][idx] = new
    
end

add_to_loop!(b::DataDictBlock, tgt, newname) = begin

    old_cat = guess_category(newname, b)
    add_to_loop!(b.underlying, tgt, newname)
    new_cat = guess_category(newname, b)
    move_category!(b, newname, old_cat, new_cat)    
    
end

create_loop!(b::DataDictBlock, names) = begin

    # Re-grouping names could change the categories they are assigned to
    old_cats = [guess_category(n, b) for n in names]

    @debug "Old categories for $names" old_cats
    
    create_loop!(b.underlying, names)
    for (o, n) in zip(old_cats, names)
        new_cat = guess_category(n, b)
        if !(n in b.cat_lookup[new_cat])
            move_category!(b, n, old_cat, new_cat)
        end
    end
    
end

# Category-based methods for DataDictBlocks

"""
Move dataname from `old_cat` to `new_cat`. Internal method. If dname not
present in old_cat, just add to new_cat. dname is already lower case.
"""
move_category!(c::DataDictBlock, dname, old_cat, new_cat) = begin

    old_cat_list = get(c.cat_lookup, old_cat, [])
    
    if dname in old_cat_list
        if old_cat == new_cat return end
        c.cat_lookup[old_cat] = filter( x -> x != dname, old_cat_list)
        if length(c.cat_lookup[old_cat]) == 0
            delete!(c.cat_lookup, old_cat)
        end
        
    end

    new_cat_list = get(c.cat_lookup, new_cat, [])
    if !(dname in new_cat_list)
        push!(new_cat_list, dname)
        c.cat_lookup[new_cat] = new_cat_list
    end
    
end


"""
    get_category_names(c::DataDictBlock, catname)

Return all data names thought to belong to `catname` in `c`. 
"""
get_category_names(c::DataDictBlock, catname) = begin
    c.cat_lookup[catname]
end

get_category(c::DataDictBlock, catname) = begin

    get_loop(c.underlying, first(get_category_names(c, catname)))
end

"""
    get_categories(c::DataDictBlock)

Return a list of all categories present in `c`
"""
get_categories(c::DataDictBlock) = begin
    keys(c.cat_lookup)
end

"""
    filter_category(c::DataDictBlock, catname, key_spec)

Return a DataFrame where only those rows of `catname` specified by `key_spec` are
present. `key_spec` is a `Dict` of data name - value pairs.
"""
filter_category(c::DataDictBlock, catname, key_spec) = begin

    df = get_category(c, catname)
    cat_keys = collect(keys(key_spec))
    
    # Now filter data frame

    filter!(df) do r
        for ck in cat_keys
            if getproperty(r, ck) != key_spec[ck]
                return false
            end
        end
        true
    end

    return df
end

filter_category(c::DataDictBlock, catname, key_spec::Dict{String}) = begin

    if !(catname in keys(c.cat_lookup)) return DataFrame() end
         
    cat_keys = collect(keys(key_spec))
    key_loc = indexin(cat_keys, get_category_names(c, catname))

    if any(isnothing, key_loc)
        throw(error("Not all datanames in $key_spec found in data block"))
    end

    newdict = map( x -> Symbol(x.first) => x.second, collect(pairs(key_spec)))
    filter_category(c, catname, Dict(newdict))
end

length(c::DataDictBlock, catname) = begin

    if catname in keys(c.cat_lookup)
        n = get_category_names(c, catname)
        return length(c[first(n)])
    else
        return 0
    end
    
end

# Utility routines for interrogating/updating data blocks based on dictionary information
# We should be aware that some non-dictionary-defined data names may be present.

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
names from child categories
"""
get_loop_names(block, catname, dict; children = false) = begin

    all_names = get_names_in_cat(dict, catname, aliases = true)
    if children
        for c in get_child_categories(dict, catname)
            append!(all_names, get_names_in_cat(dict, c))
        end
    end
    
    filter!(x -> x in keys(block) && length(block[x]) > 1, all_names)
    
end

get_loop_names(block, ::Nothing, dict; kwargs...) = String[]

count_rows(block, catname, dict) = begin
    ln = get_loop_names(block, catname, dict)
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
