
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
export DataSource,MultiDataSource, TypedDataSource
export IsDataSource
export get_julia_type_name,convert_to_julia,get_dimensions

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
    #println("Looking for entry $index of $name which has length $(length(x[name]))")
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

#==

A data source with an associated dictionary processes types and aliases.

==#

struct TypedDataSource <: DataSource
    data
    dict::abstract_cif_dictionary
end

get_dictionary(t::TypedDataSource) = t.dict
get_datasource(t::TypedDataSource) = t.data

"""
getindex(t::TypedDataSource,s::String)

The correctly-typed value for dataname `s` in `t` is returned, including
searching for dataname aliases and providing a default value if defined.
"""
Base.getindex(t::TypedDataSource,s::String) = begin
    # go through all aliases
    refdict = get_dictionary(t)
    ds = get_datasource(t)
    root_def = refdict[s]  #will find definition
    true_name = root_def["_definition.id"][1]
    raw_val = missing
    try
        raw_val = ds[true_name]
    catch KeyError
        println("Couldn't find $true_name")
        aliases = list_aliases(refdict,s)
        for a in get(root_def,"_alias.definition_id",[true_name])
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

Base.get(t::TypedDataSource,s::String,default) = begin
    try
        t[s]
    catch KeyError
        return default
    end
end


Base.iterate(t::TypedDataSource) = iterate(get_datasource(t))
Base.iterate(t::TypedDataSource,s) = iterate(get_datasource(t),s)

Base.haskey(t::TypedDataSource,s::String) = begin
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
    return unique!([translate_alias(dict,n) for n in dnames])
end

get_assoc_value(t::TypedDataSource,name,index,other_name) = begin
    # find the right names
    ds = get_datasource(t)
    dict = get_dictionary(t)
    raw_name = filter(x->haskey(ds,x),list_aliases(dict,name,include_self=true))
    raw_other = filter(x->haskey(ds,x),list_aliases(dict,other_name,include_self=true))
    if length(raw_name) == 0 || length(raw_other)==0 return missing end
    if length(raw_name) > 1 || length(raw_other) > 1
        throw(error("More than one value for $name, $other_name: $raw_name, $raw_other"))
    end
    raw = get_assoc_value(ds,raw_name[1],index,raw_other[1])
    if ismissing(raw) return missing end
    return convert_to_julia(get_dictionary(t),other_name,[raw])[]
end

get_all_associated_values(t::TypedDataSource,name,other_name) = begin
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
    return get_all_associated_values(ds,raw_name[],raw_other[])
end

#==
The dREL type machinery. Defined that take a string
as input and return an object of the appropriate type
==#

#== Type annotation ==#
const type_mapping = Dict( "Text" => String,        
                           "Code" => Symbol("CaselessString"),                                                
                           "Name" => String,        
                           "Tag"  => String,         
                           "Uri"  => String,         
                           "Date" => String,  #change later        
                           "DateTime" => String,     
                           "Version" => String,     
                           "Dimension" => Integer,   
                           "Range"  => String, #TODO       
                           "Count"  => Integer,    
                           "Index"  => Integer,       
                           "Integer" => Integer,     
                           "Real" =>    Float64,        
                           "Imag" =>    Complex,  #really?        
                           "Complex" => Complex,     
                           # Symop       
                           # Implied     
                           # ByReference
                           "Array" => Array,
                           "Matrix" => Array,
                           "List" => Array{Any}
                           )

get_julia_type_name(cdic,cat::String,obj::String) = begin
    definition = get_by_cat_obj(cdic,(cat,obj))
    base_type = definition["_type.contents"][1]
    cont_type = get(definition,"_type.container",["Single"])[1]
    julia_base_type = type_mapping[base_type]
    return julia_base_type,cont_type
end

"""Convert to the julia type for a given category, object and String value.
This is clearly insufficient as it only handles one level of arrays.

The value is assumed to be an array containing string values of the particular 
dataname, which is as usually returned by the CIF readers, even for single values.
"""
convert_to_julia(cdic,cat,obj,value::Array) = begin
    julia_base_type,cont_type = get_julia_type_name(cdic,cat,obj)
    if typeof(value) == Array{julia_base_type,1} return value end
    change_func = (x->x)
    # println("Julia type for $base_type is $julia_base_type, converting $value")
    if julia_base_type == Integer
        change_func = (x -> map(y->parse(Int,y),x))
    elseif julia_base_type == Float64
        change_func = (x -> map(y->real_from_meas(y),x))
    elseif julia_base_type == Complex
        change_func = (x -> map(y->parse(Complex{Float64},y),x))   #TODO: SU on values
    elseif julia_base_type == String
        change_func = (x -> map(y->String(y),x))
    elseif julia_base_type == Symbol("CaselessString")
        change_func = (x -> map(y->CaselessString(y),x))
    end
    if cont_type == "Single"
        return change_func(value)
    elseif cont_type in ["Array","Matrix"]
        return map(change_func,value)
    else error("Unsupported container type $cont_type")   #we can do nothing
    end
end

convert_to_julia(cdic,dataname::String,value) = begin
    definition = cdic[dataname]
    return convert_to_julia(cdic,definition["_name.category_id"][1],definition["_name.object_id"][1],value)
end

# return dimensions as an Array. Note that we do not handle
# asterisks, I think they are no longer allowed?
# The first dimension in Julia is number of rows, then number
# of columns. This is the opposite to dREL

get_dimensions(cdic,cat,obj) = begin
    definition = get_by_cat_obj(cdic,(cat,obj))
    dims = get(definition,"_type.dimension",["[]"])[1]
    final = eval(Meta.parse(dims))
    if length(final) > 1
        t = final[1]
        final[1] = final[2]
        final[2] = t
    end
    return final
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

#== This type of string compares as a caseless string
Most other operations are left undefined for now ==#

struct CaselessString <: AbstractString
    actual_string::String
end

Base.:(==)(a::CaselessString,b::AbstractString) = begin
    lowercase(a.actual_string) == lowercase(b)
end

Base.:(==)(a::AbstractString,b::CaselessString) = begin
    lowercase(a) == lowercase(b.actual_string)
end

Base.:(==)(a::CaselessString,b::CaselessString) = lowercase(a)==lowercase(b)

#== the following don't work, for now we have explicit types 
Base.:(==)(a::AbstractString,b::SubString{T} where {T}) = a == T(b)

Base.:(==)(a::SubString{T} where {T},b::AbstractString) = T(a) == b
==#

Base.:(==)(a::SubString{CaselessString},b::AbstractString) = CaselessString(a) == b
Base.:(==)(a::AbstractString,b::SubString{CaselessString}) = CaselessString(b) == a
Base.:(==)(a::CaselessString,b::SubString{CaselessString}) = a == CaselessString(b)

Base.iterate(c::CaselessString) = iterate(c.actual_string)
Base.iterate(c::CaselessString,s::Integer) = iterate(c.actual_string,s)
Base.ncodeunits(c::CaselessString) = ncodeunits(c.actual_string)
Base.isvalid(c::CaselessString,i::Integer) = isvalid(c.actual_string,i)
Base.codeunit(c::CaselessString) = codeunit(c.actual_string)

#== A caseless string should match both upper and lower case
==#
Base.getindex(d::Dict{String,Any},key::SubString{CaselessString}) = begin
    for (k,v) in d
        if lowercase(k) == lowercase(key)
            return v
        end
    end
    KeyError("$key not found")
end

#
#== End of Data Sources ==#

