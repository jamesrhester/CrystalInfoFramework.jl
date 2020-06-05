export generate_index,generate_keys
export AbstractRelationalContainer,RelationalContainer,DDLmCategory, CatPacket
export get_key_datanames,get_value, get_all_datanames

# Relations

""" 
A Relation is an object in a RelationalContainer (see below). It
corresponds to an object in a mathematical category, or a relation in
the relational model. Objects must have an identifier function that
provides an opaque label for an object. We also want to be able to
iterate over all values of this identifier, and other relations will
pass us values of this identifier. Iteration produces a Row object.
 """

abstract type Relation end
abstract type Row end

get_name(r::Relation) = throw(error("Not implemented"))

"""
Iterate over the identifier for the relation
"""
Base.iterate(r::Relation)::Row = throw(error("Not implemented"))

Base.iterate(r::Relation,s)::Row = throw(error("Not implemented"))

"""
Return all known mappings from a Relation
"""
get_mappings(r::Relation) = begin
    throw(error("Not implemented"))
end

"""
get_key_datanames returns a list of columns for the relation that, combined,
form the key. Column names must be symbols to allow rows to be selected using
other value types.
"""
get_key_datanames(r::Relation) = begin
    throw(error("Not implemented"))
end

get_category(r::Row) = throw(error("Not implemented"))

"""
Given an opaque row returned by iterator,
provide the value that it maps to for mapname
"""
get_value(row::Row,mapname) = begin
    throw(error("Not implemented"))
end

get_key(row::Row) = begin
    kd = get_key_datanames(get_category(row))
    [get_value(row,k) for k in kd]
end

"""
Given a Julia dictionary `k` containing values of
the keys, provide the corresponding value
of dataname `name`.
"""
get_value(r::Relation,k::Dict,name) = begin
    if Set(keys(k)) != Set(get_key_datanames(r))
        throw(error("Incorrect key column names supplied: $(keys(k)) != $(get_key_datanames(r))"))
    end
    test_keys = keys(k)
    test_vals = values(k)
    for row in r
        test = get_key(row)
        if all(x->x[1]==x[2],zip(test, test_vals))
            return get_value(row,name)
        end
    end
    return missing
end

Base.propertynames(c::Row,private::Bool=false) = begin
    get_object_names(get_category(c))
end

Base.getproperty(r::Row,obj::Symbol) = get_value(r,obj)

"""
A RelationalContainer models a system of interconnected tables conforming
the relational model, with an eye on the functional representation and
category theory.  The dictionary is used to establish inter-category links
and category keys. Any alias and type information is ignored. If this
information is relevant, the data source must handle it (e.g. by using
a TypedDataSource).

"""
abstract type AbstractRelationalContainer <: AbstractDict{String,Relation} end

struct RelationalContainer <: AbstractRelationalContainer
    relations::Dict{String,Relation}
    mappings::Array{Tuple{String,String,String}} #source,target,name
    RelationalContainer(d::Dict,m::Array) = new(d,m)
end

RelationalContainer(d,dict::abstract_cif_dictionary) = RelationalContainer(DataSource(d),d,dict)

RelationalContainer(d::DataSource, dict::abstract_cif_dictionary) = RelationalContainer(IsDataSource(),d,dict)

RelationalContainer(::IsDataSource,d,dict::abstract_cif_dictionary) = begin
    all_maps = Array[]
    # Construct relations
    relation_dict = Dict{String,Relation}()
    all_dnames = Set(keys(d))
    for one_cat in get_categories(dict)
        println("Processing $one_cat")
        cat_type = get(dict[one_cat],"_definition.class",["Datum"])[]
        if cat_type == "Set"
            all_names = get_names_in_cat(dict,one_cat)
            if any(n -> n in all_names, all_dnames)
                relation_dict[one_cat] = DDLmCategory(one_cat,d,dict)
            end
        elseif cat_type == "Loop"
            all_names = get_keys_for_cat(dict,one_cat)
            if all(k -> k in all_dnames,all_names)
                println("* Adding $one_cat to relational container")
                relation_dict[one_cat] = DDLmCategory(one_cat,d,dict)
            end
        end
        # Construct mappings
        all_maps = get_mappings(dict,one_cat)
    end
    RelationalContainer(relation_dict,all_maps)
end

Base.keys(r::RelationalContainer) = keys(r.relations)
Base.haskey(r::RelationalContainer,k) = haskey(r.relations,k)
Base.getindex(r::RelationalContainer,s) = r.relations[s]
Base.setindex!(r::RelationalContainer,s,new) = r.relations[s]=new

get_all_datanames(r::RelationalContainer) = begin
    namelist = []
    for one_r in values(r.relations)
        append!(namelist,keys(one_r))
    end
    return namelist
end


Base.show(io::IO,r::RelationalContainer) = begin
    show(io,r.relations)
    show(io,r.mappings)
end

"""
A CifCategory describes a relation using a dictionary
"""
abstract type CifCategory <: Relation end

# implement the Relation interface

"""
A mapping is a (src,tgt,name) tuple, but
the source is always this category
"""
get_mappings(d::abstract_cif_dictionary,cat::String) = begin
    objs = get_objs_in_cat(d,cat)
    links = get_linked_names_in_cat(d,cat)
    link_objs = [d[l]["_name.object_id"] for l in links]
    dests = [get_ultimate_link(d,l) for l in links]
    dest_cats = [find_category(d,dn) for dn in dests]
    local_maps = [(cat,cat,n) for n in objs if !(n in link_objs)]
    append!(local_maps,[(cat,d,n) for (d,n) in zip(dest_cats,dests)])
    return local_maps
end

# Useful for Set categories
first_packet(c::CifCategory) = iterate(c)[1]

# And a CifCategory has a dictionary!
CrystalInfoFramework.get_dictionary(c::CifCategory) = throw(error("Implement get_dictionary for $(typeof(c))"))

#=========

CatPackets

=========#

#==
A `CatPacket` is a row in the category. We allow access to separate elements of
the packet using the property notation.
==#

struct CatPacket <: Row
    id::Int
    source_cat::CifCategory
end

# Create a packet given the key values

CatPacket(c::CifCategory,keydict) = get_row(c,keydict)
get_category(c::CatPacket) = getfield(c,:source_cat)

CrystalInfoFramework.get_dictionary(c::CatPacket) = return get_dictionary(getfield(c,:source_cat))


get_row(r::Relation,k::Dict) = begin
    if Set(keys(k)) != Set(get_key_datanames(r))
        throw(error("Incorrect key column names supplied: $(keys(k)) != $(get_key_datanames(r))"))
    end
    test_keys = keys(k)
    test_vals = values(k)
    for row in r
        test = get_key(row)
        if all(x->x[1]==x[2],zip(test, test_vals))
            return row
        end
    end
    return missing
end

Base.iterate(c::CifCategory) = begin
    k = get_key_datanames(c)[1]
    keylength = length(c[k])
    if keylength == 0
        return nothing
    end
    r,s = iterate(1:keylength)
    return CatPacket(r,c),(1:keylength,s)
end

# Cache the final value at the end of the iteration,
# as our packets may have updated the data frame.
Base.iterate(c::CifCategory,ci) = begin
    er,s = ci
    next = iterate(er,s)
    if next == nothing
        # find new cache entries
        # update_cache(c)
        return next
    end
    r,s = next
    return CatPacket(r,c),(er,s)
end

Base.length(c::CifCategory) = size(c.data_ptr,1)

# Support dREL legacy. Current row in dREL actually
# numbers from zero
current_row(c::CatPacket) = begin
    return getfield(c,:id)-1
end

"""

"""
get_value(row::CatPacket,name) = begin
    rownum = getfield(row,:id)
    c = get_category(row)
    c[name][rownum]
end

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
    column_names::Array{Symbol,1}
    keys::Array{Symbol,1}
    rawdata
    data_ptr::DataFrame
    name_to_object::Dict{String,Symbol}
    object_to_name::Dict{Symbol,String}
    dictionary::Cifdic
end

Base.show(io::IO,d::DDLmCategory) = begin
    show(io,"DDLmCategory $(d.name) ")
    show(io,d.data_ptr)
end

    
DataSource(DDLmCategory) = IsDataSource()

"""
Construct a category from a data source and a dictionary. Type and alias information
should be handled by the datasource.
"""
DDLmCategory(catname::String,data,cifdic::Cifdic) = begin
    #
    # Absorb dictionary information
    # 
    object_names = [lowercase(a) for a in keys(cifdic) if lowercase(get(cifdic[a],"_name.category_id",[""])[1]) == lowercase(catname)]
    data_names = lowercase.([cifdic[a]["_definition.id"][1] for a in object_names])
    internal_object_names = Symbol.(lowercase.([cifdic[a]["_name.object_id"][1] for a in data_names]))
    name_to_object = Dict(zip(data_names,internal_object_names))
    object_to_name = Dict(zip(internal_object_names,data_names))
    key_names = get_keys_for_cat(cifdic,catname)
    
    # The leaf values that will go into the data frame
    # Use unique as aliases might have produced multiple occurrences
    
    have_vals = unique(filter(k-> haskey(data,k) && !(k in key_names),data_names))

    # Make the data frame
    data_ptr = DataFrame()
    println("For $catname datasource has names $have_vals")
    key_list = generate_keys(data,cifdic,key_names,have_vals)
    if !isempty(key_list)
        key_cols = zip(key_list...)
        for (n,c) in zip(key_names,key_cols)
            println("Setting $n to $c")
            data_ptr[!,name_to_object[n]] = [c...]
        end
    end

    for n in have_vals
        println("Setting $n")
        data_ptr[!,name_to_object[n]] = [generate_index(data,cifdic,key_list,key_names,n)...]
    end
    #
    # Keys are provided as symbols referring to column names
    #
    key_names = [name_to_object[k] for k in key_names]
    DDLmCategory(catname,internal_object_names,key_names,data,data_ptr,
                            name_to_object,object_to_name,cifdic)

end

DDLmCategory(catname,c::cif_container_with_dict) = DDLmCategory(catname,get_datablock(c),get_dictionary(c))

# Minimal initialiser
DDLmCategory(catname::String,cifdic::cif_container_with_dict) = DDLmCategory(catname,Dict{String,Any}(),cifdic)
 
DDLmCategory(catname::String,t::TypedDataSource) = DDLmCategory(catname,get_datasource(t),get_dictionary(t))

"""
Generate all known key values for a category. Make sure empty data works as well. "Nothing" sorts
to the end arbitrarily
"""

Base.isless(x::Nothing,y) = false
Base.isless(x,y::Nothing) = true
Base.isless(x::Nothing,y::Nothing) = false

generate_keys(data,c::Cifdic,key_names,non_key_names) = begin
    if isempty(key_names) return [] end
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
    if isempty(key_names) return [1] end
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
category if necessary. Make sure empty category is handled.
"""
get_assoc_with_key_aliases(data,c::Cifdic,name,key_name) = begin
    while !haskey(data,key_name) && key_name != nothing
        println("Looking for $key_name")
        key_name = get(c[key_name],"_name.linked_item_id",[nothing])[]
    end
    if isnothing(key_name)
        if haskey(data,name) return missing end
        return []    #the data name is missing
    end
    return get_all_associated_values(data,name,key_name)
end

# DataSource interface

get_name(d::DDLmCategory) = d.name

"""
get_data(d::DDLmCategory,colname) differs from getting the data out of the
dataframe because of linked data names (note yet implemented).

"""
Base.getindex(d::DDLmCategory,keyval) = begin
    a = get_key_datanames(d)
    if length(a) != 1
        throw(error("Category $(d.name) accessed with value $keyval but has $(length(a)) key datanames"))
    end
    return d[Dict{Symbol,Any}(a[1]=>keyval)]
end

Base.getindex(d::DDLmCategory,dict::Dict{Symbol,Any}) = begin
    get_row(d,dict)
end

# Getindex by symbol is the only way to get at a column. We reserve
# other values for row and key based indexing.

Base.getindex(d::DDLmCategory,name::Symbol) = begin
    if !(name in names(d.data_ptr)) throw(KeyError()) end
    if name in get_key_datanames(d)
        return d.data_ptr[!,name]
    end
    aka = d.object_to_name[name]
    return map(x->d.rawdata[aka][x],d.data_ptr[!,name])
end

# If a single value is provided we turn it into a keyed access as long as
# we have a single value for the key

get_by_key_val(d::DDLmCategory,x::Union{SubString,String,Array{Any},Number}) = begin
    knames = get_key_datanames(d)
    if length(knames) == 1
        rownum = indexin([x],d[knames[1]])[1]
        return CatPacket(rownum,d)
    end
    throw(KeyError(x))
end

# Relation interface.
get_value(row::CatPacket,name::String) = begin
    rownum = getfield(row,:id)
    d = get_category(row)
    colname = d.name_to_object[name]
    lookup = d.data_ptr[rownum,Symbol(colname)]
    # println("Got $lookup for pos $id of $colname")
    # The table holds the actual key value for key columns only
    if colname in get_key_datanames(d)
        return lookup
    end
    return d.rawdata[name][lookup]
end

get_value(row::CatPacket,name::Symbol) = begin
    d = get_category(row)
    rownum = getfield(row,:id)
    lookup = d.data_ptr[rownum,name]
    if name in get_key_datanames(d)
        return lookup
    end
    as_string = d.object_to_name[name]
    return d.rawdata[as_string][lookup]
end

"""
Return a list of key dataname values
"""
get_key(row::CatPacket) = begin
    d = get_category(row)
    colnames = get_key_datanames(d)
    rownum = getfield(row,:id)
    return [d.data_ptr[rownum,c] for c in colnames]
end

get_object_names(d::DDLmCategory) = d.data_ptr.names
get_key_datanames(d::DDLmCategory) = d.keys
get_link_names(d::DDLmCategory) = d.linked_names
get_dictionary(d::DDLmCategory) = d.dictionary

Base.keys(d::DDLmCategory) = names(d.data_ptr)
