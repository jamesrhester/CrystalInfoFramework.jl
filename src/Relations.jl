export generate_index,generate_keys
export DDLmCategory
export get_key_datanames,get_value_for_id,get_value_for_key

# Relations

""" A Relation is an object in a RelationalContainer (see below). It
corresponds to an object in a mathematical category, or a relation in
the relational model. Objects must have an identifier function that
provides an opaque label for an object. We also want to be able to
iterate over all values of this identifier, and other relations will
pass us values of this identifier.  """

abstract type Relation end

get_name(r::Relation) = throw(error("Not implemented"))

"""
Iterate over the identifier for the relation
"""
Base.iterate(r::Relation) = throw(error("Not implemented"))

Base.iterate(r::Relation,s) = throw(error("Not implemented"))

"""
Return all known mappings from a Relation
"""
get_mappings(r::Relation) = begin
    throw(error("Not implemented"))
end

"""
Given an opaque identifier returned by iterator,
provide the value that it maps to for mapname
"""
get_value_for_id(r::Relation,id,mapname) = begin
    throw(error("Not implemented"))
end

"""
Given a Julia dictionary `k` containing values of
the keys, provide the corresponding value
of dataname `name`.
"""
get_value_for_key(r::Relation,k,name) = begin
    if Set(keys(k)) != Set(get_key_datanames(r))
        throw(error("Incorrect key column names supplied: $(keys(k)) != $(get_key_datanames(r))"))
    end
    test_keys = keys(k)
    test_vals = values(k)
    for row in r
        test = get_key_for_id(r,row)
        if all(x->x[1]==x[2],zip(test, test_vals))
            return get_value_for_id(r,row,name)
        end
    end
    return missing
end

"""
A RelationalContainer models a system of interconnected tables conforming
the relational model, with an eye on the functional representation and
category theory.

"""
abstract type AbstractRelationalContainer <: AbstractDict{String,Relation} end

struct RelationalContainer <: AbstractRelationalContainer
    relations::Dict{String,Relation}
    mappings::Array{Tuple{String,String,String}} #source,target,name
end

RelationalContainer(a::Array{Relation,1}) = begin
    lookup = Dict([(get_name(b)=>b) for b in a])
    mappings = []
    for r in a
        tgt,name = get_mappings(r)
        push!(mappings,(get_name(r),tgt,name))
    end
    RelationalContainer(lookup,mappings)
end

Base.keys(r::RelationalContainer) = keys(r.relations)
Base.haskey(r::RelationalContainer,k) = haskey(r.relations,k)


"""
A CifCategory describes a relation
"""
abstract type CifCategory <: Relation end

# implement the Relation interface

""" 
We make use of the fact that columns are ordered
"""
Base.iterate(c::CifCategory) = begin
    k = get_key_datanames(c)[1]
    keylength = length(c[k])
    if keylength == 0
        return nothing
    end
    r,s = iterate(1:keylength)
    return r,(1:keylength,s)
end

Base.iterate(c::CifCategory,state) = begin
    keyrange,index = state
    r = iterate(keyrange,index)
    if r == nothing return nothing end
    t,s = r
    return t,(keyrange,s)
end

"""
A mapping is a (src,tgt,name) tuple, but
the source is always this category
"""
get_mappings(c::CifCategory) = begin
    myname = get_name(c)
    objs = get_object_names(c)
    links = get_link_names(c)
    linknames = [l[2] for l in links]
    local_maps = [(myname,n) for n in objs if !(n in linknames)]
    append!(local_maps,linknames)
    return local_maps
end

get_value_for_id(c::CifCategory,id,mapname) = c[mapname][id]

"""
get_data returns a value for a given category. Note that if the value
points to a different category, then it must be the id value for that
category, i.e. the order in which that value appears in the key
data name column.
"""
get_data(c::CifCategory,mapname) = throw(error("Not implemented"))
get_link_names(c::CifCategory) = throw(error("Not implemented"))

struct DDLmCategory <: CifCategory
    name::String
    column_names::Array{String,1}
    keys::Array{String,1}
    linked_names::Array{Tuple{String,String},1} #cat,dataname
    rawdata
    data_ptr::DataFrame
    name_to_object::Dict{String,String}
    object_to_name::Dict{String,String}
end

Base.show(io::IO,d::DDLmCategory) = begin
    show(io,"DDLmCategory $(d.name) ")
    show(io,d.data_ptr)
end

    
DataSource(DDLmCategory) = IsDataSource()

"""
Construct a category from a data source and a dictionary.
"""
DDLmCategory(catname::String,data,cifdic::Cifdic) = begin
    # Create tables to translate between data names and object names
    object_names = [lowercase(a) for a in keys(cifdic) if lowercase(get(cifdic[a],"_name.category_id",[""])[1]) == lowercase(catname)]
    data_names = lowercase.([cifdic[a]["_definition.id"][1] for a in object_names])
    internal_object_names = lowercase.([cifdic[a]["_name.object_id"][1] for a in data_names])
    name_to_object = Dict(zip(data_names,internal_object_names))
    object_to_name = Dict(zip(internal_object_names,data_names))
    # Do we expect more than one packet?
    is_looped = get(cifdic[catname],"_definition.class",["Set"])[1] == "Loop"
    key_names = []
    if is_looped
        key_names = cifdic[catname]["_category_key.name"]
    end

    # The leaf values that will go into the data frame
    have_vals = [k for k in data_names if k in lowercase.(keys(data)) && !(k in key_names)]

    # Make the data frame
    data_ptr = DataFrame() 
    key_tuples = generate_keys(data,cifdic,key_names,have_vals)
    key_cols = zip(key_tuples...)
    for (n,c) in zip(key_names,key_cols)
        println("Setting $n to $c")
        data_ptr[!,Symbol(name_to_object[n])] = [c...]
    end

    for n in have_vals
        println("Setting $n")
        data_ptr[!,Symbol(name_to_object[n])] = [generate_index(data,cifdic,key_tuples,key_names,n)...]
    end
    #

    # Store any linked data names

    linked_names = [(a,cifdic[a]["_name.linked_item_id"][1]) for a in data_names if
                    haskey(cifdic[a],"_name.linked_item_id") && cifdic[a]["_type.purpose"][1] != "SU"]
    linked_names = [(lowercase(cifdic[n]["_name.category_id"][1]),d) for (d,n) in linked_names]

    DDLmCategory(catname,internal_object_names,key_names,linked_names,data,data_ptr,
                            name_to_object,object_to_name)

end

DDLmCategory(catname,c::cif_container_with_dict) = DDLmCategory(catname,get_datablock(c),get_dictionary(c))

"""
Generate all known key values for a category
"""
generate_keys(data,c::Cifdic,key_names,non_key_names) = begin
    val_list = []
    for nk in non_key_names
        append!(val_list,zip([get_assoc_with_key_aliases(data,c,nk,k) for k in key_names]...))
        sort!(val_list)
        unique!(val_list)
    end
    return val_list   #is sorted
end

"""
Given a list of keys, find which position in the `non_key_name` list corresponds to
each key.
"""
generate_index(data, c::Cifdic,key_vals,key_names, non_key_name) = begin
    map_list = collect(zip((get_assoc_with_key_aliases(data,c,non_key_name,k) for k in key_names)...))
    # Map_list is a list of non-key positions -> key position. We want the opposite.
    # println("List of associations is $map_list")
    data_to_key = indexin(map_list,key_vals)
    # println("Key positions for data items: $data_to_key")
    key_to_data = indexin(collect(1:length(key_vals)),data_to_key)
    return key_to_data
end

"""
This allows seamless presentation of parent-child categories as a single
category if necessary.
"""
get_assoc_with_key_aliases(data,c::Cifdic,name,key_name) = begin
    while !haskey(data,key_name) && key_name != nothing
        println("Looking for $key_name")
        key_name = get(c[key_name],"_name.linked_item_id",[nothing])[1]
        println("Next up is $key_name")
    end
    if isnothing(key_name) return missing end
    return get_all_associated_values(data,name,key_name)
end

# DataSource interface

get_name(d::DDLmCategory) = d.name

"""
get_data(d::DDLmCategory,colname) differs from getting the data out of the
dataframe because we need to take into account both aliases and linked
data names.

"""
Base.getindex(d::DDLmCategory,name) = begin
    colname = Symbol(d.name_to_object[name])
    if colname in names(d.data_ptr)
        return d.data_ptr[!,Symbol(colname)]
    end
    throw(KeyError)
end

# Relation interface; `id` is the row number
get_value_for_id(d::DDLmCategory,id,name) = begin
    colname = d.name_to_object[name]
    lookup = d.data_ptr[id,Symbol(colname)]
    # println("Got $lookup for pos $id of $colname")
    # The table holds the actual key value for key columns only
    if name in get_key_datanames(d)
        return lookup
    end
    return d.rawdata[name][lookup]
end

"""
Return a proper key tuple
"""
get_key_for_id(d::DDLmCategory,id) = begin
    colnames = [d.name_to_object[n] for n in get_key_datanames(d)]
    return [d.data_ptr[id,Symbol(c)] for c in colnames]
end

get_column_names(d::DDLmCategory) = d.column_names
get_key_datanames(d::DDLmCategory) = d.keys
get_link_names(d::DDLmCategory) = d.linked_names
