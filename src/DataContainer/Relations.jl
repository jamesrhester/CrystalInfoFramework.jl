# *Definitions for Relations*

# **Exports**

export generate_index,generate_keys
export get_key_datanames,get_value, get_all_datanames, get_name, current_row
export get_category,has_category,first_packet, construct_category, get_data
export get_dictionary,get_packets
export select_namespace,get_namespaces
using CrystalInfoFramework:DDL2_Dictionary,DDLm_Dictionary

get_key(row::Row) = begin
    kd = get_key_datanames(get_category(row))
    [get_value(row,k) for k in kd]
end

"""
get_value(r::Relation,k::Dict,name)

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

# **General Relational Containers**
#
# A relational container may contain data covered by more than one
# dictionary. However, any given data source may only be described
# by a single dictionary. We store these together and disambiguate
# them using namespaces.

RelationalContainer(data,dict::AbstractCifDictionary) = begin
    nspace = get_dic_namespace(dict)
    RelationalContainer(Dict(nspace=>data),Dict(nspace=>dict))
end

RelationalContainer(data) = begin
    dict = get_dictionary(data)
    nspace = get_dic_namespace(dict)
    RelationalContainer(nspace=>data,nspace=>dict)
end

RelationalContainer(data::Array) = begin
    dics = get_dictionary.(data)
    names = get_dic_namespace.(dics)
    RelationalContainer(Dict(zip(names,data)),Dict(zip(names,dics)))
end

"""
select_namespace(r::RelationalContainer,s::String)

Return a RelationalContainer with data items from namespace `s` only
"""
select_namespace(r::RelationalContainer,s::AbstractString) = begin
   RelationalContainer(Dict(s=>r.data[s]),Dict(s=>r.dicts[s])) 
end

"""
find_namespace(r::AbstractRelationalContainer,s::AbstractString)

Return the namespace in `r` that contains items from the category `s`.
Raise an error if not found.
"""
find_namespace(r::AbstractRelationalContainer,s::AbstractString) = begin
    n = get_namespaces(r)
    if length(n) > 1
        # Work out the namespace
        n = filter(x->x in get_categories(get_dictionary(r,x)),n)
        if length(n) != 1
            throw(KeyError(s))
        end
    end
    first(n)
end

"""
get_category(r::RelationalContainer,s::String,nspace::String)

Return a DDLmCategory described by `s` in namespace `nspace` constructed 
from the contents of `r`
"""
get_category(r::AbstractRelationalContainer,one_cat::AbstractString,nspace::String) = construct_category(r,one_cat,nspace)

get_category(r::RelationalContainer,one_cat::AbstractString) = begin
    n = find_namespace(r,one_cat)     
    get_category(r,one_cat,n)
end

has_category(r::AbstractRelationalContainer,one_cat::AbstractString,nspace) = begin
    small_r = select_namespace(r,nspace)
    dict = get_dictionary(small_r,nspace)
    if any(n-> haskey(get_data(small_r),n),get_names_in_cat(dict,one_cat))
        return true
    end
    return false
end

has_category(r::AbstractRelationalContainer,one_cat::AbstractString) = begin
    any(i->has_category(r,one_cat,i),get_namespaces(r))
end

construct_category(r::RelationalContainer,one_cat::AbstractString) = begin
    nspace = find_namespace(r,one_cat)
    construct_category(r,realcat,nspace)
end

construct_category(r::AbstractRelationalContainer,one_cat::AbstractString,nspace) = begin
    small_r = select_namespace(r,nspace)
    dict = get_dictionary(r,nspace)
    cat_type = get_cat_class(dict,one_cat)
    if is_set_category(dict,one_cat) return SetCategory(one_cat,get_data(r),dict)
    elseif is_loop_category(dict,one_cat)
        all_names = get_keys_for_cat(dict,one_cat)
        if all(k -> haskey(get_data(small_r),k), all_names)
            @debug "All keys for Loop category $one_cat are in relation"
            return LoopCategory(one_cat,r,dict)
        end
    end
    if any(n-> haskey(get_data(small_r),n),get_names_in_cat(dict,one_cat))
        # A legacy loop category which is missing keys
        @debug "Legacy category $one_cat is present in relation"
        return LegacyCategory(one_cat,r,dict)
    end
    return missing
end

"""
get_packets distinguishes between Set categories and Loop categories,
returns Loop categories unchanged and returns a single packet
for Set categories.  If a category is missing, an empty array is
returned.
"""
get_packets(s::SetCategory) = first_packet(s)
get_packets(l::LoopCategory) = l
get_packets(missing) = []

keys(r::RelationalContainer) = begin
    if length(r.data) == 1
        return keys(get_data(r))
    end
    throw(error("Specify namespace for keys() of RelationalContainer"))
end

haskey(r::AbstractRelationalContainer,k) = k in keys(r)
haskey(r::AbstractRelationalContainer,k,n) = haskey(select_namespace(r,n),k)
getindex(r::AbstractRelationalContainer,s) = get_data(r)[s]
getindex(r::AbstractRelationalContainer,s,nspace) = get_data(r,nspace)[s]

"""
    get_dictionary(r::RelationalContainer)

Return the dictionary describing `r`.
"""
get_dictionary(r::RelationalContainer) = begin
    @assert length(r.dicts) == 1
    first(r.dicts).second
end

get_dictionary(r::RelationalContainer,nspace::String) = r.dicts[nspace]
    
get_data(r::RelationalContainer) = begin
    @assert length(r.data) == 1
    first(r.data).second
end

get_data(r::RelationalContainer,nspace::AbstractString) = r.data[nspace]

get_all_datanames(r::RelationalContainer) = keys(r)
get_all_datanames(r::RelationalContainer,nspace::AbstractString) = keys(get_data(r,nspace))
get_namespaces(r::RelationalContainer) = keys(r.dicts)
get_dicts(r::RelationalContainer) = r.dicts

# **Relational Containers**

show(io::IO,r::RelationalContainer) = begin
    println(io,"Relational container with data")
    println(io,"Namespaces: $(keys(r.dicts))")
end


# **CifCategory** #

# CifCategories use a CIF dictionary to describe relations
# implement the Relation interface

"""
A mapping is a (src,tgt,name) tuple, but
the source is always this category
"""
get_mappings(d::AbstractCifDictionary,cat::String) = begin
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

iterate(c::CifCategory) = begin
    if length(c) == 0 return nothing end
    r,s = iterate(1:length(c))
    return CatPacket(r,c),(1:length(c),s)
end

# Cache the final value at the end of the iteration,
# as our packets may have updated the data frame.
iterate(c::CifCategory,ci) = begin
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

length(c::CifCategory) = error("length undefined for $(typeof(c))")

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

# TODO: child categories
get_value(row::CatPacket,name::Symbol) = begin
    rownum = getfield(row,:id)
    c = get_category(row)
    c[name,rownum]
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

getindex(d::CifCategory,keyval) = begin
    a = get_key_datanames(d)
    if length(a) != 1
        throw(error("Category $(get_name(d)) accessed with value $keyval but has $(length(a)) key datanames $a"))
    end
    return d[Dict{Symbol,Any}(a[1]=>keyval)]
end

getindex(d::CifCategory,dict::Dict{Symbol,V} where V) = begin
    get_row(d,dict)
end

getindex(d::CifCategory,pairs...) = begin
    getindex(d,Dict(pairs))
end


show(io::IO,d::CifCategory) = begin
    print(io,"Category $(get_name(d)) ")
    print(io,"Length $(length(d))\n")
    df = DataFrame()
    for n in d.column_names
        if haskey(d,n)
            df[!,n] = d[n]
        end
    end
    show(io,df)
end

show(io::IO,::MIME"text/cif",d::LoopCategory) = begin
    catname = get_name(d)
    df = DataFrame(d)
    formatted = format_for_cif(df,catname)
    print(io,formatted)
end

show(io::IO,s::SetCategory) = begin
    println(io,"Category $(get_name(s))")
    for n in keys(s)
        println("$n : $(s[n][])")
    end
end

"""
LoopCategory(catname::String,data,cifdic::AbstractCifDictionary)

Construct a category from a data source and a dictionary. Type and alias information
should be handled by the datasource.
"""
LoopCategory(catname::String,data,cifdic::AbstractCifDictionary) = begin
    #
    # Absorb dictionary information
    # 
    data_names = get_names_in_cat(cifdic,catname)
    internal_object_names = Symbol.(find_object(cifdic,a) for a in data_names)
    name_to_object = Dict(zip(data_names,internal_object_names))
    object_to_name = Dict(((i,find_name(cifdic,catname,String(i))) for i in internal_object_names))
    namespace = get_dic_namespace(cifdic)
    key_names = get_keys_for_cat(cifdic,catname)
    
    # Use unique as aliases might have produced multiple occurrences
    small_data = select_namespace(data,namespace)
    have_vals = unique(filter(k-> haskey(small_data,k) && !(k in key_names),data_names))

    # println("For $catname datasource has names $have_vals")
    key_names = [name_to_object[k] for k in key_names]
    # Child categories
    child_cats = create_children(catname,data,cifdic)
    LoopCategory(catname,internal_object_names,key_names,data,
                 name_to_object,object_to_name, child_cats,
                 cifdic,namespace)

end

LoopCategory(catname::String,t::TypedDataSource) = LoopCategory(catname,get_datasource(t),get_dictionary(t))

# A legacy category was missing key values, which are provided to make it into
# a DDLm Category. It cannot have child categories.

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
                 l.object_to_name,[],
                 l.dictionary,
                 l.namespace)
end

length(d::LoopCategory) = length(d.rawdata[d.object_to_name[d.keys[1]],d.namespace])
haskey(d::LoopCategory,n::Symbol) = begin
    small_data = select_namespace(d.rawdata,d.namespace)
    haskey(small_data,get(d.object_to_name,n,"")) || any(x->haskey(small_data,get(x.object_to_name,n,"")),d.child_categories)
end
haskey(d::LoopCategory,n::AbstractString) = haskey(select_namespace(d.rawdata,d.namespace),n)

"""
Generate all known key values for a category. Make sure empty data works as well. "Nothing" sorts
to the end arbitrarily
"""

isless(x::Nothing,y) = false
isless(x,y::Nothing) = true
isless(x::Nothing,y::Nothing) = false

# DataSource interface

get_name(d::LoopCategory) = d.name

"""
get_data(d::LoopCategory,colname) differs from getting the data out of the
dataframe because of linked data names (not yet implemented).

"""

# Getindex by symbol is the only way to get at a column. We reserve
# other types for row and key based indexing.  We try all child
# categories after trying the parent category

getindex(d::LoopCategory,name::Symbol) = begin
    if name in d.column_names return d.rawdata[d.object_to_name[name],d.namespace] end
    for x in d.child_categories
        if name in x.column_names return x.rawdata[x.object_to_name[name],x.namespace] end
    end
end

getindex(d::LoopCategory,name::Symbol,index::Integer) = get_value(d,index,name)

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

"""
Get the row number for the provided key values
"""
get_rownum(d::LoopCategory,keyvals::Dict{Symbol,V} where V) = begin
    targvals = values(keyvals)
    targcols = keys(keyvals)
    for i in 1:length(d)
        testvals = zip(targvals,(d[k][i] for k in targcols))
        if all(x->isequal(x[1],x[2]),testvals) return i end
    end
    throw(KeyError(keyvals))
end

"""
get_value(d::LoopCategory,n::Int,colname::Symbol)

Return the value corresponding to row `n` of the key
datanames for `d` for `colname`.  If `colname` belongs
to a child category this will not in general be
`colname[n]`. Instead the values of the key datanames
are used to look up the correct value 
"""
get_value(d::LoopCategory,n::Int,colname::Symbol) = begin    
    if haskey(d.object_to_name,colname)
        aka = d.object_to_name[colname]
        return d.rawdata[aka,d.namespace][n]
    end
    if length(d.child_categories) == 0 throw(KeyError(colname)) end
    # Handle the children recursively
    pkeys_symb = get_key_datanames(d)
    pkeys = [(p,d.object_to_name[p]) for p in pkeys_symb]
    keyvals = Dict((p[2]=>get_value(d,n,p[1])) for p in pkeys)
    for c in d.child_categories
        try
            return get_value(c,keyvals,colname)
        catch e
            if e isa KeyError continue end
            throw(e)
        end
    end
    throw(KeyError(colname))
end

get_value(d::LoopCategory,n::Int,colname::AbstractString) = begin
    return get_value(d,n,d.name_to_object[colname])
end

# If we are given only a column name, we have to put all
# of the values in
get_value(d::LoopCategory,colname::AbstractString) = begin
    @warn "super inefficient column access"
    return [get_value(d,n,colname) for n in 1:length(d)]
end

"""
get_value(d::LoopCategory,k::Dict,name)

Return the value of `name` corresponding to the unique values
of key datanames given in `k`.
"""
get_value(d::LoopCategory,k::Dict{String,V} where V,name) = begin
    @debug "Searching for $name using $k in $(d.name)"
    if !haskey(d.object_to_name,name)
        @debug "$name not found..."
        if length(d.child_categories) > 0
            for c in d.child_categories
                try
                    return get_value(c,k,name)
                catch e
                    if e isa KeyError continue end
                    throw(e)
                end
            end
            throw(KeyError(name))
        end
    end
    key_order = get_key_datanames(d)
    dic = get_dictionary(d)
    ckeys = [(ko,d.object_to_name[ko]) for ko in key_order]
    linkvals = [(ko,get_linked_name(dic,ck)) for (ko,ck) in ckeys]
    @debug "Linkvals is $linkvals"
    linkvals = Dict((l[1] => k[l[2]]) for l in linkvals)
    @debug "Getting row number for $linkvals in $(d.name)"
    rownum = 0
    try
        rownum = get_rownum(d,linkvals)
    catch e
        if e isa KeyError return missing end
        throw(e)
    end
    @debug "Row $rownum"
    return d.rawdata[d.object_to_name[name]][rownum]
end

get_value(d::LoopCategory,k::Dict{Symbol,V} where V,name) = begin
    newdict = Dict((d.object_to_name[kk]=>v) for (kk,v) in k)
    return get_value(d,newdict,name)
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

get_object_names(d::LoopCategory) = begin
    result = copy(d.column_names)
    for x in d.child_categories
        append!(result,x.column_names)
    end
    return result
end

get_key_datanames(d::LoopCategory) = d.keys
get_link_names(d::LoopCategory) = d.linked_names
get_dictionary(d::LoopCategory) = d.dictionary

keys(d::LoopCategory) = get_object_names(d)

SetCategory(catname::String,data,cifdic::DDLm_Dictionary) = begin
    #
    # Absorb dictionary information
    #
    data_names = get_names_in_cat(cifdic,catname)
    internal_object_names = Symbol.(find_object(cifdic,a) for a in data_names)
    name_to_object = Dict(zip(data_names,internal_object_names))
    object_to_name = Dict(((i,find_name(cifdic,catname,String(i))) for i in internal_object_names))
    n = get_dic_namespace(cifdic)
    small_data = select_namespace(data,n)
    # Use unique as aliases might have produced multiple occurrences
    
    present = unique(filter(k-> haskey(small_data,k),data_names))
    present = map(x->name_to_object[x],present)
    SetCategory(catname,internal_object_names,data,present,
                name_to_object,object_to_name,
                cifdic,n)
end

get_dictionary(s::SetCategory) = s.dictionary
get_name(s::SetCategory) = s.name
get_object_names(s::SetCategory) = s.present
keys(s::SetCategory) = s.present
haskey(s::SetCategory,name::AbstractString) = name in (s.object_to_name[x] for x in keys(s))

get_value(s::SetCategory,i::Int,name::Symbol) = begin
    if i != 1
        throw(error("Attempt to access row $i of a 1-row Set Category"))
    end
    access_name = s.object_to_name[name]
    return s.rawdata[access_name]
end

getindex(s::SetCategory,name::Symbol) = begin
    return s.rawdata[s.object_to_name[name],s.namespace]
end

getindex(s::SetCategory,name::Symbol,index::Integer) = s[name][]
length(s::SetCategory) = 1

LegacyCategory(catname::AbstractString,data,cifdic::AbstractCifDictionary) = begin
    #
    # Absorb dictionary information
    # 
    data_names = get_names_in_cat(cifdic,catname)
    internal_object_names = Symbol.(find_object(cifdic,a) for a in data_names)
    name_to_object = Dict(zip(data_names,internal_object_names))
    object_to_name = Dict(((i,find_name(cifdic,catname,String(i))) for i in internal_object_names))
    n = get_dic_namespace(cifdic)
    small_data = select_namespace(data,n)
    # The leaf values that will go into the data frame
    # Use unique as aliases might have produced multiple occurrences
    
    have_vals = unique(filter(k-> haskey(small_data,k),data_names))

    @debug "For $catname datasource has names $have_vals"

    LegacyCategory(catname,internal_object_names,data,
                            name_to_object,object_to_name,cifdic,n)
end

# Getindex by symbol is the only way to get at a column. We reserve
# other values for row and key based indexing.

Base.getindex(l::LegacyCategory,name::Symbol) = begin
    if !haskey(l,name) throw(KeyError(name)) end
    aka = l.object_to_name[name]
    return l.rawdata[aka]
end

Base.length(l::LegacyCategory) = length(l[first(keys(l))])

get_dictionary(l::LegacyCategory) = l.dictionary

get_name(l::LegacyCategory) = l.name

Base.keys(l::LegacyCategory) = begin
(k for k in l.column_names if haskey(l.rawdata,l.object_to_name[k]))
end

haskey(l::LegacyCategory,k) = k in keys(l)  

"""

Given the category name, return an array of loop categories that are children
of the supplied category
"""
create_children(name::AbstractString,data,cifdic) = begin
    child_names = get_child_categories(cifdic,name)
    return [LoopCategory(c,data,cifdic) for c in child_names]
end

"""
Create a DataFrame from a Loop Category. Child categories are ignored. If `canonical`
is true, canonical names are used instead of the default object names
"""
DataFrames.DataFrame(l::LoopCategory;canonical=false) = begin
    nspace = l.namespace
    rawnames = [l.object_to_name[o] for o in l.column_names if haskey(l.rawdata,l.object_to_name[o])]
    rawdata = [l.rawdata[r,nspace] for r in rawnames]
    if canonical
        DataFrames.DataFrame(rawdata,rawnames,copycols=false)
    else
        objects = [l.name_to_object[q] for q in rawnames]
        DataFrames.DataFrame(rawdata,objects,copycols=false)
    end
end

DataFrames.DataFrame(s::SetCategory;canonical=false) = begin
    nspace = s.namespace
    rawnames = [s.object_to_name[o] for o in s.column_names if haskey(s.rawdata,s.object_to_name[o])]
    rawdata = [s.rawdata[r,nspace] for r in rawnames]
    if canonical
        DataFrames.DataFrame(rawdata,rawnames,copycols=false)
    else
        objects = [s.name_to_object[q] for q in rawnames]
        DataFrames.DataFrame(rawdata,objects,copycols=false)
    end
end

"""
DDLm_Dictionary(ds,att_dic::DDLm_Dictionary,dividers)

Create a `DDLm_Dictionary` from `ds`, using the category scheme and
attributes in `att_dic`, sorting definitions based on the attributes in
`dividers`.  ds must contain `_dictionary.title`
"""
DDLm_Dictionary(ds,att_dic::DDLm_Dictionary,dividers) = begin
    dicname = ds["_dictionary.title"][]
    nspace = haskey(ds,"_dictionary.namespace") ? ds["_dictionary.namespace"][] : "ddlm"
    att_cats = get_categories(att_dic)
    att_info = Dict{Symbol,DataFrames.DataFrame}()
    #println("Cached values: $(ds.value_cache["ddlm"])")
    @debug "All cats: $att_cats"
    for ac in att_cats
        @debug "Preparing category $ac"
        if has_category(ds,ac,"ddlm") println("We have category $ac") end
        catinfo = get_category(ds,ac,"ddlm")
        @debug "We have catinfo $(typeof(catinfo)) $catinfo"
        if ismissing(catinfo) continue end
        df = unique!(DataFrame(catinfo))
        att_info[Symbol(ac)] = df
    end
#==    for d in dividers
        tab_name = Symbol(find_category(att_dic,d))
        col_name = Symbol(find_object(att_dic,d))
        println("For $d have $(att_info[tab_name])")
        att_info[tab_name].master_id = att_info[tab_name][!,col_name]   
end ==#
    for (tab,cols) in att_info
        if !(:master_id in propertynames(cols))
            @debug "Adding a master_id to $tab"
            att_info[tab].master_id = dicname
        end
        # master_id always lower case
        att_info[tab].master_id = lowercase.(att_info[tab].master_id)
    end
    # make sure there is a head category
    h = find_head_category(att_info)
    if !(lowercase(h) in lowercase.(att_info[:definition][!,:id]))
        add_head_category!(att_info,h)
    end
    DDLm_Dictionary(att_info,nspace)
end

"""
DDL2_Dictionary(ds,att_dic::DDL2_Dictionary,dividers)

Create a `DDL2_Dictionary` from `ds`, using the category scheme and
attributes in `att_dic`, sorting definitions based on the attributes in
`dividers`.  ds must contain `_dictionary.title`
"""
DDL2_Dictionary(ds,att_dic,dividers) = begin
    dicname = ds["_dictionary.title"][]
    nspace = "ddl2"
    att_cats = get_categories(att_dic)
    att_info = Dict{Symbol,DataFrames.DataFrame}()
    #println("Cached values: $(ds.value_cache["ddlm"])")
    println("All cats: $att_cats")
    for ac in att_cats
        println("Preparing category $ac")
        if has_category(ds,ac,"ddl2") println("We have category $ac") end
        catinfo = get_category(ds,ac,"ddl2")
        println("We have catinfo $catinfo")
        if ismissing(catinfo) || length(catinfo) == 0 continue end
        df = unique!(DataFrame(catinfo))
        att_info[Symbol(ac)] = df
    end
#==    for d in dividers
        tab_name = Symbol(find_category(att_dic,d))
        col_name = Symbol(find_object(att_dic,d))
        println("For $d have $(att_info[tab_name])")
        att_info[tab_name].master_id = att_info[tab_name][!,col_name]   
end ==#
    for (tab,cols) in att_info
        if !(:master_id in propertynames(cols))
            println("Adding a master_id to $tab")
            att_info[tab].master_id = dicname
        end
    end
    DDL2_Dictionary(att_info,nspace)
end

