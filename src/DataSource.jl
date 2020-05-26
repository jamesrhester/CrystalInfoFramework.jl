
"""
# DataSources and Relational Data Sources

A DataSource is a generic source of data that is capable
only of providing an array of values and stating which
values could be associated with which other values.

A RelationalDataSource builds on this by providing 
associations from multiple arrays to single arrays, and
from single arrays to multiple arrays.
"""

export get_assoc_value, get_all_associated_values
export DataSource,MultiDataSource

"""
## Data Source

Ultimately a DataSource holds values that are associated
with other values. This association is by location, not
intrinsic to the value itself.

A DataSource returns ordered arrays of information when
supplied with a data name. It additionally returns the
corresponding values of other data names when supplied
with an index.  This correspondence is opportunistic,
and does not need to be meaningful.

A DataSource may contain encapsulated DataSources.

We implement DataSources as traits to allow them to be
grafted onto other file formats.

"""
abstract type DataSource end
struct IsDataSource <: DataSource end
struct IsNotDataSource <: DataSource end

DataSource(::Type) = IsNotDataSource()

"""
Return the value of `other_name` for position `index` of the array returned
for `name`, which is mapped from `other_name`. If there is no such mapping, error.  
"""
get_assoc_value(x,n,i,o) = get_assoc_value(DataSource(x),x,n,i,o)
get_assoc_value(::IsNotDataSource,x,n,i,o) = error("$(typeof(x)) is not a DataSource")


"""
Get all values of `o` associated with `n` such that the ith entry of `n`
corresponds to the ith entry of `o`.
"""
get_all_associated_values(x,n,o) = get_all_associated_values(DataSource(x),x,n,o)

"""
For simplicity we do not try to overload Dict methods as some of the types
that we are grafting onto may themselves use these methods to access data.
The following are dictionary methods with `ds` prepended.
"""
ds_get(x,n,default) = begin
    try
        return ds_getindex(x,n)
    catch KeyError
        return default
    end
end

ds_getindex(x,n) = ds_getindex(DataSource(x),x,n)

ds_length(x,n) = ds_length(DataSource(x),x,n)

"""
Convenience function: return all associated values of `other_name`. Should
be reimplemented for efficiency.
"""
get_all_associated_values(::IsDataSource,ds,name::String,other_name::String) = begin
    total = length(ds[name])
    return [get_assoc_value(ds,name,i,other_name) for i in 1:total]
end

"""
Multiple data sources are also data sources. This trait can be applied to preexisting
data storage formats, and then logic here will be used to handle creation of
associations between data names in component data sources.

The multi-data-source is conceived as a container holding data sources.

Value associations within siblings are preserved. Therefore it is not
possible in general to match indices in arrays in order to obtain
corresponding values, as some siblings may have no values for a data
name that has them in another sibling.

Scenarios:
1. 3 siblings, empty parent, one sibling contains many singleton values
-> all singleton values are associated with values in the remaining blocks
1. As above, siblings contain differing singleton values for a data name
-> association will be with anything having the same number of values, and
with values within each sibling block
1. As above, one sibling contains an association between data names, another
has only one of the data names and so no association
-> The parent retains the association in the sibling that has it
1. Siblings and a contentful parent: parent is just another data block
"""
struct MultiDataSource{T} <: DataSource
    wrapped::T
end

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

        
get_assoc_value(x::MultiDataSource,name,index,other_name) = begin
    if length(x[other_name]) == 1
        return x[other_name][1]
    end
    cnt = 0
    for d in x
        #println("Looking for assoc value in $(typeof(d))")
        #println("Which is what iterating over $(typeof(x)) gives us")
        if !haskey(d,name) || !haskey(d,other_name) continue end
        new_len = length(d[name])
        if cnt+new_len < index
            cnt+= new_len
            continue
        end
        nested_assoc = get_assoc_value(d,name,index-cnt,other_name)
        return nested_assoc
    end
    return missing
end

get_all_associated_values(x::MultiDataSource,name,other_name) = begin
    ds = x.wrapped
    if length(x[other_name]) == 1
        return fill(x[other_name][1],length(x[name]))
    end
    ret_list = []
    for d in x
        new_len = length(d[name])
        println("Length: $new_len")
        if new_len == length(d[other_name])
            println("Appending values for $other_name")
            append!(ret_list, d[other_name])
        elseif length(d[other_name]) == 1
            append!(ret_list,fill(d[other_name][1],length(d[name])))
        else
            append!(ret_list,fill(missing,length(d[name])))
        end
    end
    return ret_list
end

"""
A Cif NativeBlock is a data source. It implements the dictionary interface.
"""
DataSource(::NativeBlock) = IsDataSource()

get_assoc_value(x::NativeBlock,name,index,other) = begin
    if !haskey(x,name) return missing end
    if !haskey(x,other) return missing end
    println("Looking for entry $index of $name which has length $(length(x[name]))")
    if index > length(x[name]) throw(BoundsError) end
    if length(x[other]) == 1 return x[other][1] end
    if length(x[name]) == length(x[other]) return x[other][index] end 
end

"""
To use anything but NativeBlocks as DataSources we must make them into
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
    return NativeBlock(c),saves
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

iterate_blocks(c::NativeCif) = begin
    blocks = keys(get_contents(c))
    n = Base.iterate(blocks)
    if n == nothing return nothing end
    nxt,s = n
    println("Iterating NativeCif of length $(length(blocks))")
    return make_data_source(get_contents(c)[nxt]),(blocks,s)
end

iterate_blocks(c::NativeCif,s) = begin
    blocks,nk = s
    n = Base.iterate(blocks,nk)
    if n == nothing
        return nothing
    end
    nxt,new_s = n
    return make_data_source(get_contents(c)[nxt]),(blocks,new_s)
end

#== End of Data Sources ==#
==#
