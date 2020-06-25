export generate_index,generate_keys
export get_key_datanames,get_value, get_all_datanames, get_name, current_row
export get_category,has_category,first_packet

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
    key_order = get_key_datanames(r)
    numkeys = length(key_order)
    if Set(keys(k)) != Set(key_order)
        throw(error("Incorrect key column names supplied: $(keys(k)) != $(key_order)"))
    end
    for row in r
        test = get_key(row)  #same order
        if all(x->k[key_order[x]]==test[x],1:numkeys)
            return get_value(row,name)
        end
    end
    return missing
end

get_row(r::Relation,k::Dict) = begin
    key_order = get_key_datanames(r)
    numkeys = length(key_order)
    if Set(keys(k)) != Set(key_order)
        throw(error("Incorrect key column names supplied: $(keys(k)) != $key_order"))
    end
    test_keys = keys(k)
    test_vals = values(k)
    for row in r
        test = get_key(row)
        if all(x->test[x]==k[key_order[x]],1:numkeys)
            return row
        end
    end
    return missing
end

Base.propertynames(c::Row,private::Bool=false) = begin
    get_object_names(get_category(c))
end

Base.getproperty(r::Row,obj::Symbol) = get_value(r,obj)

# == Relational Containers == #

RelationalContainer(d,dict::abstract_cif_dictionary) = RelationalContainer(DataSource(d),d,dict)

RelationalContainer(d::DataSource, dict::abstract_cif_dictionary) = RelationalContainer(IsDataSource(),d,dict)

RelationalContainer(::IsDataSource,d,dict::abstract_cif_dictionary) = begin
    all_maps = Array[]
    # Construct relations
    relation_dict = Dict{String,Relation}()
    all_dnames = Set(lowercase.(keys(d)))
    for one_cat in get_categories(dict)
        println("Processing $one_cat")
        cat_type = get(dict[one_cat],"_definition.class",["Datum"])[]
        if cat_type == "Set"
            all_names = lowercase.(get_names_in_cat(dict,one_cat))
            if any(n -> n in all_names, all_dnames)
                println("* Adding Set category $one_cat to container")
                relation_dict[one_cat] = SetCategory(one_cat,d,dict)
            end
        elseif cat_type == "Loop"
            all_names = get_keys_for_cat(dict,one_cat)
            if all(k -> k in all_dnames,all_names)
                println("* Adding $one_cat to relational container")
                relation_dict[one_cat] = LoopCategory(one_cat,d,dict)
            elseif any(n->n in all_dnames,get_names_in_cat(dict,one_cat))
                # A legacy loop category which is missing keys
                println("* Adding legacy category $one_cat to container")
                relation_dict[one_cat] = LegacyCategory(one_cat,d,dict)
            end
        end
        # Construct mappings
        all_maps = get_mappings(dict,one_cat)
    end
    RelationalContainer(relation_dict,all_maps,get_all_datanames(relation_dict))
end

Base.keys(r::RelationalContainer) = keys(r.dataname_to_cat)
Base.haskey(r::RelationalContainer,k) = k in keys(r)
Base.getindex(r::RelationalContainer,s) = begin
    cat = r.dataname_to_cat[s]
    get_value(r.relations[cat],s)
end

get_all_datanames(r) = begin
    namelist = Dict{String,String}()
    for one_r in values(r)
        merge!(namelist,Dict([(one_r.object_to_name[k]=>get_name(one_r)) for k in keys(one_r)]))
    end
    return namelist
end

get_category(r::RelationalContainer,s::String) = r.relations[s]
has_category(r::RelationalContainer,s::String) = haskey(r.relations,s)

Base.show(io::IO,r::RelationalContainer) = begin
    show(io,r.relations)
    show(io,r.mappings)
end

# == CifCategory == #

#== 

CifCategories use a CIF dictionary to describe relations

==#

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

# == CatPacket == #

# Create a packet given the key values

CatPacket(c::CifCategory,keydict) = get_row(c,keydict)

get_category(c::CatPacket) = getfield(c,:source_cat)
get_dictionary(c::CatPacket) = return get_dictionary(getfield(c,:source_cat))

Base.iterate(c::CifCategory) = begin
    r,s = iterate(1:length(c))
    return CatPacket(r,c),(1:length(c),s)
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

Base.length(c::CifCategory) = error("length undefined for $(typeof(c))")

"""
get_value(CifCategory,n::Int,colname::Symbol) returns the actual value for the
item in the nth position of colname. Usually for internal use only, as the
order in which items appear is not guaranteed
"""
get_value(c::CifCategory,n::Int,colname::Symbol) = error("Define get_value for $(typeof(c))")

"""
current_row(c::CatPacket)
 
Support dREL legacy. Current row in dREL actually
numbers from zero
"""
current_row(c::CatPacket) = begin
    return getfield(c,:id)-1
end

get_value(row::CatPacket,name) = begin
    rownum = getfield(row,:id)
    c = get_category(row)
    c[name][rownum]
end

# Relation interface.
get_value(row::CatPacket,name::String) = begin
    rownum = getfield(row,:id)
    d = get_category(row)
    return get_value(d,rownum,name)
end

"""
get_data returns a value for a given category. Note that if the value
points to a different category, then it must be the id value for that
category, i.e. the order in which that value appears in the key
data name column.
"""
get_data(c::CifCategory,mapname) = throw(error("Not implemented"))
get_link_names(c::CifCategory) = throw(error("Not implemented"))

Base.show(io::IO,d::LoopCategory) = begin
    print(io,"LoopCategory $(d.name) ")
    print(io,"Length $(length(d))")
    print(io,"Columns $(d.column_names)")
end


"""
Construct a category from a data source and a dictionary. Type and alias information
should be handled by the datasource.
"""
LoopCategory(catname::String,data,cifdic::Cifdic) = begin
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

    println("For $catname datasource has names $have_vals")
    #
    # Keys are provided as symbols referring to column names
    #
    #
    # Coherency check: all associated keys should have the same length
    #
    all_lengths = unique(length(data[k]) for k in have_vals)
    if length(all_lengths)> 1
        error("Inconsistent columns for $catname: $all_lengths")
    end
    if length(have_vals) > 0
        keylengths = unique(length.(get_all_associated_indices(data,have_vals[1],k) for k in key_names))
        if length(keylengths) > 1
            error("Inconsistent key lengths for $catname: $keylengths")
        end
        if keylengths[] != all_lengths[]
            error("For $catname key length $keylengths does not match value length: $all_lengths")
        end
    end
    key_names = [name_to_object[k] for k in key_names]

    LoopCategory(catname,internal_object_names,key_names,data,
                            name_to_object,object_to_name,cifdic)

end

LoopCategory(catname,c::cif_container_with_dict) = LoopCategory(catname,get_datablock(c),get_dictionary(c))

# Minimal initialiser
LoopCategory(catname::String,cifdic::cif_container_with_dict) = LoopCategory(catname,Dict{String,Any}(),cifdic)
 
LoopCategory(catname::String,t::TypedDataSource) = LoopCategory(catname,get_datasource(t),get_dictionary(t))

# A legacy category was missing key values, which are provided to make it into
# a DDLm Category
LoopCategory(l::LegacyCategory,k) = begin
    keyname = get_keys_for_cat(get_dictionary(l),get_name(l))
    if length(keyname)!=1
        throw(error("Can only convert LegacyCategory to LoopCategory if single key, given $keyname"))
    end
    keyname = l.name_to_object[keyname[1]]
    LoopCategory(l.name,
                 l.column_names,
                 [keyname],
                 l.rawdata,
                 l.name_to_object,
                 l.object_to_name,
                 l.dictionary)
end

Base.length(d::LoopCategory) = length(d.rawdata[d.object_to_name[d.keys[1]]])

"""
Generate all known key values for a category. Make sure empty data works as well. "Nothing" sorts
to the end arbitrarily
"""

Base.isless(x::Nothing,y) = false
Base.isless(x,y::Nothing) = true
Base.isless(x::Nothing,y::Nothing) = false

# DataSource interface

get_name(d::LoopCategory) = d.name

"""
get_data(d::LoopCategory,colname) differs from getting the data out of the
dataframe because of linked data names (note yet implemented).

"""
Base.getindex(d::CifCategory,keyval) = begin
    a = get_key_datanames(d)
    if length(a) != 1
        throw(error("Category $(get_name(d)) accessed with value $keyval but has $(length(a)) key datanames"))
    end
    return d[Dict{Symbol,Any}(a[1]=>keyval)]
end

Base.getindex(d::CifCategory,dict::Dict{Symbol,V} where V) = begin
    get_row(d,dict)
end

# Getindex by symbol is the only way to get at a column. We reserve
# other values for row and key based indexing.

Base.getindex(d::LoopCategory,name::Symbol) = begin
    if !(name in d.column_names) throw(KeyError(name)) end
    aka = d.object_to_name[name]
    return d.rawdata[aka]
end

# If a single value is provided we turn it into a keyed access as long as
# we have a single value for the key

get_by_key_val(d::LoopCategory,x::Union{SubString,String,Array{Any},Number}) = begin
    knames = get_key_datanames(d)
    if length(knames) == 1
        rownum = indexin([x],d[knames[1]])[1]
        return CatPacket(rownum,d)
    end
    throw(KeyError(x))
end

get_value(d::LoopCategory,n::Int,colname::Symbol) = begin
    aka = d.object_to_name[colname]
    return get_value(d,n,aka)
end

get_value(d::LoopCategory,n::Int,colname::String) = begin
    return d.rawdata[colname][n]
end

# If we are given only a column name, we have to put all
# of the values in
get_value(d::LoopCategory,colname::String) = begin
    return [get_value(d,n,colname) for n in 1:length(d)]
end
               
get_value(row::CatPacket,name::Symbol) = begin
    d = get_category(row)
    rownum = getfield(row,:id)
    return get_value(d,rownum,name)
end

"""
Return a list of key dataname values
"""
get_key(row::CatPacket) = begin
    d = get_category(row)
    colnames = get_key_datanames(d)
    rownum = getfield(row,:id)
    return [get_value(d,rownum,c) for c in colnames]
end

get_object_names(d::LoopCategory) = d.column_names
get_key_datanames(d::LoopCategory) = d.keys
get_link_names(d::LoopCategory) = d.linked_names
get_dictionary(d::LoopCategory) = d.dictionary

Base.keys(d::LoopCategory) = get_object_names(d)

SetCategory(catname::String,data,cifdic::Cifdic) = begin
    #
    # Absorb dictionary information
    # 
    object_names = [lowercase(a) for a in keys(cifdic) if lowercase(get(cifdic[a],"_name.category_id",[""])[1]) == lowercase(catname)]
    data_names = lowercase.([cifdic[a]["_definition.id"][1] for a in object_names])
    internal_object_names = Symbol.(lowercase.([cifdic[a]["_name.object_id"][1] for a in data_names]))
    name_to_object = Dict(zip(data_names,internal_object_names))
    object_to_name = Dict(zip(internal_object_names,data_names))

    # Use unique as aliases might have produced multiple occurrences
    
    present = unique(filter(k-> haskey(data,k),data_names))
    present = map(x->name_to_object[x],present)
    SetCategory(catname,internal_object_names,data,present,
                            name_to_object,object_to_name,cifdic)
end

get_dictionary(s::SetCategory) = s.dictionary
get_name(s::SetCategory) = s.name
get_object_names(s::SetCategory) = s.present
Base.keys(s::SetCategory) = s.present

get_value(s::SetCategory,i::Int,name::Symbol) = begin
    if i != 1
        throw(error("Attempt to access row $i of a 1-row Set Category"))
    end
    access_name = s.object_to_name[name]
    return s.rawdata[access_name]
end

Base.getindex(s::SetCategory,name::Symbol) = begin
    return s.rawdata[s.object_to_name[name]]
end

Base.length(s::SetCategory) = 1

LegacyCategory(catname::String,data,cifdic::Cifdic) = begin
    #
    # Absorb dictionary information
    # 
    object_names = [lowercase(a) for a in keys(cifdic) if lowercase(get(cifdic[a],"_name.category_id",[""])[1]) == lowercase(catname)]
    data_names = lowercase.([cifdic[a]["_definition.id"][1] for a in object_names])
    internal_object_names = Symbol.(lowercase.([cifdic[a]["_name.object_id"][1] for a in data_names]))
    name_to_object = Dict(zip(data_names,internal_object_names))
    object_to_name = Dict(zip(internal_object_names,data_names))

    # The leaf values that will go into the data frame
    # Use unique as aliases might have produced multiple occurrences
    
    have_vals = unique(filter(k-> haskey(data,k),data_names))

    println("For $catname datasource has names $have_vals")

    LegacyCategory(catname,internal_object_names,data,
                            name_to_object,object_to_name,cifdic)
end

Base.length(l::LegacyCategory) = length(l[l.column_names[1]])

get_dictionary(l::LegacyCategory) = l.dictionary

get_name(l::LegacyCategory) = l.name

Base.keys(l::LegacyCategory) = l.column_names
