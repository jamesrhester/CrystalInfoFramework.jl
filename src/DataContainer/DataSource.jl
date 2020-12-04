
# *DataSources and Relational Data Sources*

# A DataSource is a generic source of data that is capable
# only of providing an array of values indexed by name.

# **Exports**
export get_assoc_index, get_all_associated_indices
export get_assoc_value, get_all_associated_values
export get_namespaces

"""
get_namespaces(x)

Return the designators for the namespaces from which the names used to
access the data are drawn.
"""
get_namespaces(x) = [""]
select_namespace(x,s) = x

"""
Return the index into `other_name` for position `index` of the array returned
for `name`, which is mapped from `other_name`. If there is no such mapping, error.  
"""
get_assoc_index(x,n,i,o) = get_assoc_index(DataSource(x),x,n,i,o)
get_assoc_index(::IsNotDataSource,x,n,i,o) = error("$(typeof(x)) is not a DataSource")
get_assoc_index(::IsDataSource,x,n,i,o) = begin
    if !haskey(x,n) return missing end
    name_len = length(x[n])
    if !haskey(x,o) return missing end
    other_len = length(x[o])
    if name_len == other_len return i end
    if other_len == 1 return 1 end
    return missing
end

get_assoc_value(x,n,i,o) = get_assoc_value(DataSource(x),x,n,i,o)
get_assoc_value(::IsDataSource,x,n,i,o) = x[o][get_assoc_index(IsDataSource(),x,n,i,o)]

"""
Get all values of `o` associated with `n` such that the ith entry of `n`
corresponds to the ith entry of `o`.
"""
get_all_associated_indices(x,n,o) = get_all_associated_indices(DataSource(x),x,n,o)

"""
Default method: return all associated values of `other_name` assuming that like
indices match, or that a single value of `other_name` will be associated with 
all values of `name`.
"""
get_all_associated_indices(::IsDataSource,ds,name::String,other_name::String) = begin
    if !haskey(ds,name) return [] end
    name_len = length(ds[name])
    if !haskey(ds,other_name) return fill(missing,name_len) end
    other_len = length(ds[other_name])
    if name_len == other_len return 1:other_len end
    if other_len == 1 return fill(1,name_len) end
    return []
end

get_all_associated_values(x,n,o) =
    (get_assoc_value(x,n,i,o) for i in get_all_associated_indices(x,n,o))

# == Dict methods == #

"""
A dictionary is a data source
"""
DataSource(::AbstractDict) = IsDataSource()

# == MultiDataSource methods == 

make_data_source(x::MultiDataSource) = x

make_data_source(x) = make_data_source(DataSource(x),x)

make_data_source(::IsDataSource,x) = begin
    if ismissing(iterate_blocks(x)) return x end
    return MultiDataSource(x)
end

"""
Return an iterator over constituent blocks, which themselves conform to the
DataSource interface
"""

Base.iterate(x::MultiDataSource) = iterate_blocks(x.wrapped)
Base.iterate(x::MultiDataSource,s) = iterate_blocks(x.wrapped,s)

"""
Provide an iterator over components 
"""
iterate_blocks(ds) = missing

Base.get(ds::MultiDataSource,n,default) = begin
    try
        return ds[n]
    catch KeyError
        return default
    end
end

Base.getindex(ds::MultiDataSource,n) = begin
    returnvals = []
    println("Looking for $n")
    for d in ds
        #println("Looking for $n in $(typeof(d))")
        append!(returnvals,get(d,n,[]))
    end
    println("Found $(length(returnvals)) values")
    if length(returnvals) == 0 throw(KeyError) end
    return returnvals
end

Base.length(x::MultiDataSource,name) = begin
    ds = x.wrapped
    cnt = 0
    print("Length of $name is ") 
    for d in ds
        cnt += length(get(d,name,[]))
    end
    println("$cnt")
    return cnt
end

Base.keys(x::MultiDataSource) = begin
    all_keys = Set([])
    for d in x
        union!(all_keys,keys(d))
    end
    return all_keys
end

Base.haskey(x::MultiDataSource,k) = begin
    for d in x
        if haskey(d,k) return true end
    end
    return false
end

        
get_assoc_index(x::MultiDataSource,name,index,other_name) = begin
    if length(x[other_name]) == 1
        return 1
    end
    cnt = 0     #index in name
    o_cnt = 0   #index in other one
    for d in x
        #println("Looking for assoc value in $(typeof(d))")
        #println("Which is what iterating over $(typeof(x)) gives us")
        if !haskey(d,name) && !haskey(d,other_name) continue end
        if haskey(d,name)
            new_len = length(d[name])
            if cnt+new_len < index
                cnt+= new_len
                if haskey(d,other_name)
                    o_cnt += length(d[other_name])
                end
                continue
            else
                nested_assoc = get_assoc_index(d,name,index-cnt,other_name)
                return o_cnt + nested_assoc
            end
        end
        if cnt > index # gone past
            break
        end
    end
    return missing
end

get_all_associated_indices(x::MultiDataSource,name,other_name) = begin
    if length(x[other_name]) == 1
        return fill(1,length(x[name]))
    end
    ret_list = []
    o_cnt = 0
    for d in x
        if !haskey(d,name) && !haskey(d,other_name) continue end
        if haskey(d,name) && haskey(d,other_name)
            append!(ret_list, o_cnt .+ get_all_associated_indices(d,name,other_name))
            o_cnt += length(d[other_name])
        elseif haskey(d,other_name)
            o_cnt += length(d[other_name])
        elseif haskey(d,name)
            append!(ret_list,fill(missing,length(d[name])))
        end
    end
    return ret_list
end

"""
A Cif Block is a data source. It implements the dictionary interface.
"""
DataSource(::Block) = IsDataSource()

#
# NativeBlocks have no namespaces so we ignore if supplied
#
Base.getindex(x::Block,y::AbstractString,z::AbstractString) = x[y]

"""
To use anything but Blocks as DataSources we must make them into
MultiDataSources, which means implementing the iterate_blocks method.
The blocks in a cif_container are all of the save frames, and the
enclosing block taken as a separate block.  In this view it is
possible to associate items in separate save frames. However, these
potential associations are excluded if necessary by dictionaries. 
"""
iterate_blocks(c::nested_cif_container) = begin
    # main block then saves
    saves = collect(keys(get_frames(c)))
    #println("Returning iterator over $(typeof(c)), length $(length(saves))")
    return Block(c),saves
end

iterate_blocks(c::nested_cif_container,s) = begin
    #println("Next iteration over $(typeof(c)), length $(length(s)) left")
    if length(s) == 0
        println("Finished iteration")
        return nothing
    end
    next_frame = popfirst!(s)
    #println("Now looking at frame $next_frame")
    return get_frames(c)[next_frame],s
end

"""
A CifFile is a MultiDataSource. We have to create concrete types as
indexing is defined differently.
"""

iterate_blocks(c::Cif) = begin
    blocks = keys(get_contents(c))
    n = Base.iterate(blocks)
    if n == nothing return nothing end
    nxt,s = n
    println("Iterating Cif of length $(length(blocks))")
    return make_data_source(get_contents(c)[nxt]),(blocks,s)
end

iterate_blocks(c::Cif,s) = begin
    blocks,nk = s
    n = Base.iterate(blocks,nk)
    if n == nothing
        return nothing
    end
    nxt,new_s = n
    return make_data_source(get_contents(c)[nxt]),(blocks,new_s)
end

# **TypedDataSource**

get_dictionary(t::TypedDataSource) = t.dict
get_datasource(t::TypedDataSource) = t.data
get_namespaces(t::TypedDataSource) = [get_dic_namespace(get_dictionary(t))]
select_namespace(t::TypedDataSource,nspace) = begin
    if nspace != get_namespaces(t)[]
        throw(KeyError(t))
    end
    t
end

select_namespace(t::NamespacedTypedDataSource,nspace) = begin
    t.data[nspace]
end

"""
getindex(t::TypedDataSource,s::String)

The correctly-typed value for dataname `s` in `t` is returned, including
searching for dataname aliases and providing a default value if defined.
"""
Base.getindex(t::TypedDataSource,s::AbstractString) = begin
    # go through all aliases
    refdict = get_dictionary(t)
    ds = get_datasource(t)
    root_def = refdict[s]  #will find definition
    true_name = find_name(refdict,s)
    raw_val = missing
    try
        raw_val = ds[true_name]
    catch KeyError
        println("Couldn't find $true_name")
        aliases = list_aliases(refdict,s;include_self=true)
        for a in aliases
            try
                raw_val = ds[a]
                break
            catch KeyError
                println("And couldn't find $a")
            end
        end
        if ismissing(raw_val)   #no joy
            backup = get_default(refdict,s)
            if !ismissing(backup)
                raw_val = backup
            else
                println("Can't find $s")
                throw(Base.KeyError(s))
            end
        end
    end
    actual_type = convert_to_julia(refdict,s,raw_val)
end

Base.getindex(t::TypedDataSource,s,n) = t[s]  #no namespaces

Base.getindex(t::NamespacedTypedDataSource,s::AbstractString,n::AbstractString) = begin
    select_namespace(t,n)[s]
end

Base.get(t::TypedDataSource,s::AbstractString,default) = begin
    try
        t[s]
    catch KeyError
        return default
    end
end


Base.iterate(t::TypedDataSource) = iterate(get_datasource(t))
Base.iterate(t::TypedDataSource,s) = iterate(get_datasource(t),s)

Base.haskey(t::TypedDataSource,s::AbstractString) = begin
    actual_data = get_datasource(t)
    # go through all aliases
    ref_dic = get_dictionary(t)
    if !(haskey(ref_dic,s)) #no alias information
        return haskey(actual_data,s)
    end
    return any(n->haskey(actual_data,n), list_aliases(ref_dic,s,include_self=true))
end

# Anything not defined in the dictionary is invisible
# Convert all non-standard data names.

Base.keys(t::TypedDataSource) = begin
    true_keys = lowercase.(collect(keys(get_datasource(t))))
    dict = get_dictionary(t)
    dnames = [d for d in keys(dict) if lowercase(d) in true_keys]
    return unique!([find_name(dict,n) for n in dnames])
end

"""
get_assoc_index(t::TypedDataSource,name,index,other_name)

Return the index of the value in `t[other_name]` corresponding to `name[i]`.
If `other_name` has linked key values they will also be checked if `name` is missing.
The intended use is for `other_name` to be a linked key data name.
"""
get_assoc_index(t::TypedDataSource,name,index,other_name) = begin
    # find the right names
    ds = get_datasource(t)
    dict = get_dictionary(t)
    raw_name = filter(x->haskey(ds,x),list_aliases(dict,name,include_self=true))
    raw_other = filter(x->haskey(ds,x),list_aliases(dict,other_name,include_self=true))
    if length(raw_other) == 0
        # try for linked names now
        raw_other = nothing
        while !haskey(ds,raw_other) && raw_other != nothing
            raw_other = get_parent_name(dict,raw_other)
        end
        if raw_other == nothing
            return missing
        end
        raw_other = [raw_other]
    end
    if length(raw_name) > 1 || length(raw_other) > 1
        throw(error("More than one value for $name, $other_name: $raw_name, $raw_other"))
    end
    return get_assoc_index(ds,raw_name[1],index,raw_other[1])
end

get_all_associated_indices(t::TypedDataSource,name,other_name) = begin
    # find the right names
    ds = get_datasource(t)
    dict = get_dictionary(t)
    raw_name = filter(x->haskey(ds,x),list_aliases(dict,name,include_self=true))
    raw_other = filter(x->haskey(ds,x),list_aliases(dict,other_name,include_self=true))
    if length(raw_name) == 0 || length(raw_other)==0 return missing end
    if length(raw_name) > 1 || length(raw_other) > 1
        throw(error("More than one value for $name, $other_name: $raw_name, $raw_other"))
    end
    println("Getting all linked values for $(raw_name[]) -> $(raw_other[]))")
    return get_all_associated_indices(ds,raw_name[],raw_other[])
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

#== End of Data Sources ==#

