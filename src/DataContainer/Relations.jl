# *Definitions for Relations*

# **Exports**

export generate_index, generate_keys
export get_key_datanames, get_value, get_all_datanames, get_name, current_row
export get_category, has_category, first_packet, construct_category, get_data
export get_dictionary, get_packets
export select_namespace, get_namespaces
using CrystalInfoFramework:DDL2_Dictionary, DDLm_Dictionary

get_key(row::Row) = begin
    kd = get_key_datanames(get_category(row), drop_same = true)
    @debug "In get_key" kd
    [get_value(row, k) for k in kd]
end

"""
    get_value(r::Relation, k::Dict, name)

Given a Julia dictionary `k` containing values of
the keys, provide the corresponding value
of dataname `name`. 
"""
get_value(r::Relation, k::Dict, name) = begin
    key_order = get_key_datanames(r)
    numkeys = length(key_order)
    if Set(keys(k)) != Set(key_order)
        throw(error("Incorrect key column names supplied: $(keys(k)) != $(key_order)"))
    end
    for row in r
        test = get_key(row)  #same order
        if all(x->k[key_order[x]]==test[x],1:numkeys)
            return get_value(row, name)
        end
    end
    return missing
end

get_row(r::Relation, k::Dict) = begin
    key_order = get_key_datanames(r, drop_same = true)
    numkeys = length(key_order)
    if Set(keys(k)) != Set(key_order)
        throw(error("Incorrect key column names supplied: $(keys(k)) != $key_order"))
    end
    test_keys = keys(k)
    test_vals = values(k)
    for row in r
        test = get_key(row)
        @debug "Looking for row" test k
        if all(x -> test[x] == k[key_order[x]], 1:numkeys)
            return row
        end
    end
    return missing
end

Base.propertynames(c::Row,private::Bool=false) = begin
    get_object_names(get_category(c))
end

Base.getproperty(r::Row, obj::Symbol) = get_value(r, obj)

# **General Relational Containers**
#
# A relational container may contain data covered by more than one
# dictionary. However, any given data source may only be described
# by a single dictionary. We store these together and disambiguate
# them using namespaces.

RelationalContainer(data, dict::AbstractCifDictionary) = begin
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

RelationalContainer(data::Dict, dicts::Dict) = begin
    n_to_objs = Dict{String, Dict{String, Tuple{Symbol, Symbol}}}()
    objs_to_n = Dict{String, Dict{Tuple{Symbol, Symbol}, String}}()
    for (n,d) in dicts
        present = keys(data[n])

        # Include Set category keys that are missing

        add_set_cat_keys!(d, data[n], present)

        # Include implicit values
        
        expand_by_linked!(d, data[n], present)
        
        info = ((Symbol(find_category(d, a)), Symbol(find_object(d, a))) for a in present)
        n_to_objs[n] = Dict(zip(present, info))
        canonical_names = (find_name(d, first(i), last(i)) for i in info)
        objs_to_n[n] = Dict(zip(info, canonical_names))
    end

    RelationalContainer(data, dicts, n_to_objs, objs_to_n)
end

"""
    add_set_cat_keys!(dictionary, data, start)

Add key data names for Set categories that have a single row or are missing.
"""
add_set_cat_keys!(dict, data, start) = begin
    ss = get_set_categories(dict)
    filter!(ss) do x
        l = get_keys_for_cat(dict, x)
        if length(l) != 1 || l[] in start
            false
        elseif get_linked_name(dict, l[]) != l[]
            false
        else
            present = intersect(get_names_in_cat(dict, x), keys(data))
            length(present) == 0 || length(data[first(present)]) == 1
        end
    end

    extra_keys = [get_keys_for_cat(dict, x)[] for x in ss]

    for k in extra_keys
        data[k] = ["unique"]
    end
    
    append!(start, extra_keys)

end

"""
    expand_by_linked(dictionary, data, start)

Expand data name list `start` to include any data names that are
children of single-valued data names that are present. TODO: parents
as well.
"""
expand_by_linked!(dict, data, start::Array) = begin
    extra = []
    for one_name in start
        if length(data[one_name]) != 1 continue end
        gdc = get_dataname_children(dict, one_name)
        append!(extra, filter(x -> !(x in start), gdc))
    end
    append!(start, extra)
end

"""
select_namespace(r::RelationalContainer,s::String)

Return a RelationalContainer with data items from namespace `s` only
"""
select_namespace(r::RelationalContainer, s::AbstractString) = begin
    RelationalContainer(Dict(s=>r.data[s]), Dict(s=>r.dicts[s]), Dict(s => r.name_to_catobj[s]),
                        Dict(s => r.catobj_to_name[s]))
end

"""
find_namespace(r::AbstractRelationalContainer,s::AbstractString)

Return the namespace in `r` that contains items from the category `s`.
Raise an error if not found.
"""
find_namespace(r::AbstractRelationalContainer, s::AbstractString) = begin
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
get_category(r::RelationalContainer, s::String, nspace::String)

Return a DDLmCategory described by `s` in namespace `nspace` constructed 
from the contents of `r`
"""
get_category(r::AbstractRelationalContainer, one_cat::AbstractString, nspace::String) = construct_category(r, one_cat, nspace)

get_category(r::RelationalContainer, one_cat::AbstractString) = begin
    n = find_namespace(r, one_cat)     
    get_category(r, one_cat, n)
end

has_category(r::AbstractRelationalContainer, one_cat::AbstractString, nspace) = begin
    small_r = select_namespace(r, nspace)
    dict = get_dictionary(small_r, nspace)
    if any(n-> haskey(get_data(small_r),n), get_names_in_cat(dict,one_cat))
        return true
    end
    return false
end

has_category(r::AbstractRelationalContainer, one_cat::AbstractString) = begin
    any(i -> has_category(r, one_cat, i), get_namespaces(r))
end

construct_category(r::RelationalContainer,one_cat::AbstractString) = begin

    nspace = find_namespace(r, one_cat)
    construct_category(r, realcat, nspace)

end

construct_category(r::AbstractRelationalContainer, one_cat::AbstractString, nspace) = begin

    small_r = select_namespace(r, nspace)
    dict = get_dictionary(r, nspace)
    cat_type = get_cat_class(dict, one_cat)
    all_names = get_keys_for_cat(dict,one_cat)  # empty for single-block Set cats
    if all(k -> haskey(get_data(small_r),k), all_names)
        @debug "All keys for Loop category $one_cat are in relation"
        return LoopCategory(r, one_cat, nspace)
    end
    
    if any(n-> haskey(get_data(small_r),n), get_names_in_cat(dict,one_cat))
        # A legacy loop category which is missing keys
        @debug "Legacy category $one_cat is present in relation"
        @warn "Must create key data name for $one_cat"
        return LoopCategory(r, one_cat, nspace)
    end
    
    return missing
end

"""
get_packets distinguishes between Set categories and Loop categories,
returns Loop categories unchanged and returns a single packet
for Set categories.  If a category is missing, an empty array is
returned.
"""
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
getindex(r::AbstractRelationalContainer, s, nspace) = select_namespace(r,nspace)[s]

getindex(r::AbstractRelationalContainer, k) = begin

    # If k is in the data, return that

    dta = get_data(r)
    if haskey(dta, k) return dta[k] end

    # Otherwise see if it is a child data name of something that is there and
    # single-valued

    d = get_dictionary(r)
    l = get_ultimate_link(d, k)
    if l != k
        prt_val = r[l]   # key error if missing
        if length(prt_val) > 1
            throw(KeyError(k))
        end

        # Now calculate the necessary length

        c = find_category(d, k)
        ks = get_keys_for_cat(d, c)
        present = intersect(get_names_in_cat(d, c), keys(r))
        filter!(x -> haskey(dta, x), ks)

        # Deal with set categories having implicit keys
        
        if length(ks) == 0
            if length(present) > 0
                testval = dta[present[1]]
                if length(testval) == 1
                    return prt_val
                end
            end
            throw(KeyError(k))
        end
        
        ls = map(x -> length(dta[x]), ks)
        unique!(ls)
        if length(ls) != 1
            error("Inconsistent number of data values for $ks: $ls")
        end

        return fill(prt_val[], ls[])
    end
    
    throw(KeyError(k))
end

"""
    get_dictionary(r::RelationalContainer)

Return the dictionary describing `r`.
"""
get_dictionary(r::RelationalContainer) = begin
    @assert length(r.dicts) == 1
    first(r.dicts).second
end

get_dictionary(r::RelationalContainer, nspace::String) = r.dicts[nspace]
    
get_data(r::RelationalContainer) = begin
    @assert length(r.data) == 1
    first(r.data).second
end

get_data(r::RelationalContainer, nspace::AbstractString) = r.data[nspace]

get_all_datanames(r::RelationalContainer) = keys(r)
get_all_datanames(r::RelationalContainer, nspace::AbstractString) = keys(get_data(r,nspace))
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
get_mappings(d::AbstractCifDictionary, cat::String) = begin
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

CatPacket(c::CifCategory, keydict) = get_row(c, keydict)

get_category(c::CatPacket) = getfield(c, :source_cat)

get_dictionary(c::CatPacket) = return get_dictionary(getfield(c, :source_cat))

show(io::IO,cp::CatPacket) = begin
    c = get_category(cp)
    for n in c.column_names
        println(io,"$n: $(c[n][getfield(cp,:id)])")
    end
end

iterate(c::CifCategory) = begin
    if length(c) == 0 return nothing end
    r, s = iterate(1:length(c))
    return CatPacket(r, c), (1:length(c), s)
end

# Cache the final value at the end of the iteration,
# as our packets may have updated the data frame.
iterate(c::CifCategory, ci) = begin
    er, s = ci
    next = iterate(er, s)
    if next == nothing
        # find new cache entries
        # update_cache(c)
        return next
    end
    r, s = next
    return CatPacket(r,c), (er,s)
end

length(c::CifCategory) = error("length undefined for $(typeof(c))")

"""
get_value(CifCategory, n::Int, colname::Symbol) returns the actual value for the
item in the nth position of colname. Usually for internal use only, as the
order in which items appear is not guaranteed
"""
get_value(c::CifCategory, n::Int, colname::Symbol) = error("Define get_value for $(typeof(c))")

"""
current_row(c::CatPacket)
 
Support dREL legacy. Current row in dREL actually
numbers from zero
"""
current_row(c::CatPacket) = begin
    return getfield(c,:id) - 1
end

# TODO: child categories
get_value(row::CatPacket, name::Symbol) = begin
    rownum = getfield(row,:id)
    c = get_category(row)
    c[name,rownum]
end

# Relation interface.
get_value(row::CatPacket, name::String) = begin
    rownum = getfield(row,:id)
    d = get_category(row)
    return get_value(d, rownum, name)
end

"""
get_data returns a value for a given category. Note that if the value
points to a different category, then it must be the id value for that
category, i.e. the order in which that value appears in the key
data name column.
"""
get_data(c::CifCategory, mapname) = throw(error("Not implemented"))

get_link_names(c::CifCategory) = throw(error("Not implemented"))

get_container(c::CifCategory) = throw(error("Not implemented"))

getindex(d::CifCategory, keyval) = begin

    a = get_key_datanames(d, drop_same = true)
    if length(a) != 1
        throw(error("Category $(get_name(d)) accessed with value $keyval but has $(length(a)) key datanames $a"))
    end
    return d[Dict{Symbol,Any}(a[1]=>keyval)]
end

getindex(d::CifCategory, dict::Dict{Symbol,V} where V) = begin
    get_row(d, dict)
end

getindex(d::CifCategory, pairs...) = begin
    getindex(d, Dict(pairs))
end

show(io::IO, d::CifCategory) = begin
    print(io,"Category $(get_name(d)) ")
    print(io,"Length $(length(d))\n")
    df = DataFrame()
    small_r = get_container(d)
    nspace = d.namespace
    catname = get_name(d)
    for n in d.column_names
        nn = small_r.catobj_to_name[nspace][catname, n]
        df[!,n] = small_r[nn]
    end
    show(io,df)
end

show(io::IO,::MIME"text/cif", d::LoopCategory) = begin
    catname = get_name(d)
    df = DataFrame(d)
    formatted = format_for_cif(df, catname = String(catname))
    print(io,formatted)
end

"""
LoopCategory(container::AbstractRelationalContainer, catname::String, namespace::String)

Construct a category from a data source and a dictionary. Type and alias information
should be handled by the datasource.
"""
LoopCategory(container::AbstractRelationalContainer, catname::String, namespace::String) = begin

    # Absorb dictionary information

    dict = container.dicts[namespace]
    data_names = get_names_in_cat(dict, catname)
    present = intersect(data_names, keys(container.name_to_catobj[namespace]))
    present_objs = [container.name_to_catobj[namespace][x][2] for x in present]
    
    # Child categories

    child_cats = create_children(container, catname, namespace)

    LoopCategory(Symbol(lowercase(catname)), namespace, present_objs, child_cats, container)

end

LoopCategory(container::AbstractRelationalContainer, catname::String) = begin
    n = get_namespace(container)
    LoopCategory(container, catname, n)
end

length(d::LoopCategory) = begin

    dic = get_dictionary(d)
    ks = get_keys_for_cat(dic, get_name(d))

    if length(ks) == 0   # Single-block Set category
        return length(d.column_names) > 0 ? 1 : 0
    end

    cont = get_container(d)
    return length(select_namespace(cont,d.namespace)[ks[1]])
    
end

haskey(d::LoopCategory, n::Symbol) = begin

    small_data = get_container(d)
    haskey(small_data, get(d.object_to_name,n,"")) || any(x -> haskey(small_data, get(x.object_to_name, n, "")), d.children)
    
end

haskey(d::LoopCategory, n::AbstractString) = haskey(get_container(d), n)

get_container(d::LoopCategory) = select_namespace(d.container, d.namespace)

get_full_container(d::LoopCategory) = d.container

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

getindex(d::LoopCategory, name::Symbol) = begin
    
    small_r = get_container(d)
    cat_name = get_name(d)
    
    if name in d.column_names
        return small_r[small_r.catobj_to_name[d.namespace][(cat_name, name)]]
    end

    for x in d.children
        cat_name = get_name(x)
        if name in x.column_names
            return small_r[small_r.catobj_to_name[d.namespace][(cat_name,name)]]
        end
    end
    throw(KeyError(name))
end

getindex(d::LoopCategory, name::Symbol, index::Integer) = get_value(d, index, name)

# If a single value is provided we turn it into a keyed access as long as
# we have a single value for the key

get_by_key_val(d::LoopCategory, x::Union{SubString,String,Array{Any},Number}) = begin

    knames = get_key_datanames(d, drop_same = true)
    if length(knames) == 1
        rownum = indexin([x],d[knames[1]])[1]
        return CatPacket(rownum,d)
    end
    throw(KeyError(x))
end

"""
Get the row number for the provided key values
"""
get_rownum(d::LoopCategory, keyvals::Dict{Symbol,V} where V) = begin
    targvals = values(keyvals)
    targcols = keys(keyvals)
    for i in 1:length(d)
        testvals = zip(targvals, (d[k][i] for k in targcols))
        if all(x -> isequal(x[1], x[2]), testvals) return i end
    end
    throw(KeyError(keyvals))
end

"""
get_value(d::LoopCategory, n::Int, colname::Symbol)

Return the value corresponding to row `n` of the key
datanames for `d` for `colname`.  If `colname` belongs
to a child category this will not in general be
`colname[n]`. Instead the values of the key datanames
are used to look up the correct value 
"""
get_value(d::LoopCategory, n::Int, colname::Symbol) = begin
    nspace = d.namespace
    arc = get_container(d)
    small_r = select_namespace(arc, nspace)
    cname = get_name(d)

    if haskey(arc.catobj_to_name[nspace], (cname, colname))
        aka = arc.catobj_to_name[nspace][cname, colname]
        return small_r[aka][n]
    end
    
    if length(d.children) == 0 throw(KeyError(colname)) end

    # Handle the children recursively

    pkeys_symb = get_key_datanames(d)
    keyvals = Dict((p => get_value(d, n, p)) for p in pkeys_symb)
    for c in d.children
        try
            return get_value(c, keyvals, colname)
        catch e
            if e isa KeyError continue end
            throw(e)
        end
    end
    throw(KeyError(colname))
end

get_value(d::LoopCategory, n::Int, colname::AbstractString) = begin
    arc = get_container(d)
    n = d.namespace
    return get_value(d, n, arc.name_to_catobj[n][colname][2])
end

# If we are given only a column name, we have to put all
# of the values in
get_value(d::LoopCategory, colname::AbstractString) = begin
    lend = length(d)
    if lend == 1
        return get_value(d, 1, colname)
    end
    
    @warn "super inefficient column access"

    return [get_value(d, n, colname) for n in 1:lend]
end

"""
get_value(d::LoopCategory, k::Dict, name)

Return the value of `name` corresponding to the unique values
of key datanames given in `k`. If a key takes a single value
it may be omitted.
"""
get_value(d::LoopCategory, k::Dict{String,V} where V, name::String) = begin

    arc = get_container(d)
    n = d.namespace

    @debug "Searching for $name using $k in $(d.name)"

    if !haskey(arc.name_to_catobj[n], name)
        @debug "$name not found..."
        cc = get_child_categories(d)
        if length(cc) > 0
            for c in cc
                try
                    return get_value(c, k, name)
                catch e
                    if e isa KeyError continue end
                    throw(e)
                end
            end
            throw(KeyError(name))
        end
    end

    key_order = get_key_datanames(d, drop_same=true)
    dic = get_dictionary(d)
    catname = get_name(d)
    ckeys = [(ko, arc.catobj_to_name[n][catname,ko]) for ko in key_order]
    linkvals = [(ko, get_linked_name(dic, ck)) for (ko, ck) in ckeys]
    
    @debug "Linkvals is $linkvals"

    linkvals = Dict((l[1] => k[l[2]]) for l in linkvals)

    @debug "Getting row number for $linkvals in $(d.name)"

    rownum = 0
    try
        rownum = get_rownum(d, linkvals)
    catch e
        if e isa KeyError return missing end
        throw(e)
    end
    @debug "Row $rownum"

    return select_namespace(arc, n)[name][rownum]
end

"""
    get_value(l::LoopCategory, k::Dict{Symbol, V}, name)

Return the value of `name` where the key values are given by the contents
of `k` as Symbols.
"""
get_value(d::LoopCategory, k::Dict{Symbol,V} where V, name::String) = begin
    catname = get_name(d)
    arc = get_container(d)
    n = d.namespace
    newdict = Dict((arc.catobj_to_name[n][catname,kk]=>v) for (kk,v) in k)
    return get_value(d, newdict, name)
end

get_value(d::LoopCategory, k::Dict, name::Symbol) = begin
    n = d.namespace
    c = get_name(d)
    get_value(d, k, get_container(d).catobj_to_name[n][c, name])
end

"""
Return a list of key dataname values
"""
get_key(row::CatPacket) = begin
    d = get_category(row)
    colnames = get_key_datanames(d, drop_same = true)
    rownum = getfield(row, :id)
    return [get_value(d, rownum, c) for c in colnames]
end

get_object_names(d::LoopCategory) = begin
    result = copy(d.column_names)
    dict = get_dictionary(d)
    arc = get_container(d)
    present = keys(arc.name_to_catobj)
    for x in get_child_categories(d)
        extra_names = intersect(get_names_in_cat(dict, x), present) 
        append!(result, map(x -> arc.name_to_catobj[x][2], extra_names))
    end
    return result
end

get_child_categories(d::LoopCategory) = begin
    dict = get_dictionary(d)
    cc = get_child_categories(dict, get_name(d))
end

"""
   get_key_datanames(d::LoopCategory; drop_same = false)

Return the key datanames for `d`. If `drop_same` is true, return only
those key datanames that could take more than one value, i.e. their
parent data names take more than one value.
"""
get_key_datanames(d::LoopCategory; drop_same = false) = begin
    dic = get_dictionary(d)
    c = get_container(d)
    n = d.namespace
    kk = get_keys_for_cat(dic, get_name(d))
    if drop_same
        filter!(kk) do k
            ul = get_ultimate_link(dic, k)
            length(unique(c[k])) > 1
        end
    end
    
    [c.name_to_catobj[n][t][2] for t in kk]
end

get_dictionary(d::LoopCategory) = get_dictionary(get_container(d))

keys(d::LoopCategory) = get_object_names(d)

"""

Given the category name, return an array of loop categories that are children
of the supplied category
"""
create_children(container, name::AbstractString, namespace) = begin
    dict = container.dicts[namespace]
    child_names = CrystalInfoFramework.get_child_categories(dict, name)
    return [LoopCategory(container, c, namespace) for c in child_names]
end

"""
Create a DataFrame from a Loop Category. Child categories are ignored. If `canonical`
is true, canonical names are used instead of the default object names
"""
DataFrames.DataFrame(l::LoopCategory; canonical=false) = begin
    nspace = l.namespace
    arc = get_container(l)
    catname = get_name(l)
    rawnames = [arc.catobj_to_name[nspace][catname,o] for o in l.column_names]
    @debug "Raw names for data frame" rawnames
    rawdata = [arc[r] for r in rawnames]
    if canonical
        DataFrames.DataFrame(rawdata, rawnames, copycols=false)
    else
        objects = [arc.name_to_catobj[nspace][q][2] for q in rawnames]
        DataFrames.DataFrame(rawdata, objects, copycols=false)
    end
end

"""
    DDLm_Dictionary(ds, att_dic::DDLm_Dictionary, dividers)

Create a `DDLm_Dictionary` from `ds`, using the category scheme and
attributes in `att_dic`, sorting definitions based on the attributes in
`dividers`.  ds must contain `_dictionary.title`
"""
DDLm_Dictionary(ds, att_dic::DDLm_Dictionary, dividers) = begin
    
    dicname = ds["_dictionary.title"][]
    nspace = haskey(ds,"_dictionary.namespace") ? ds["_dictionary.namespace"][] : "ddlm"
    att_cats = get_categories(att_dic)
    att_info = Dict{Symbol,DataFrames.DataFrame}()
    #println("Cached values: $(ds.value_cache["ddlm"])")
    @debug "All cats: $att_cats"
    for ac in att_cats
        @debug "Preparing category $ac"
        if has_category(ds,ac,"ddlm") println("We have category $ac") end
        catinfo = get_category(ds, ac, "ddlm")
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
            att_info[tab].master_id = [dicname]
        end
        # master_id always lower case
        att_info[tab].master_id = lowercase.(att_info[tab].master_id)
    end
    # make sure there is a head category
    h = find_head_category(att_info)
    if !(lowercase(h) in lowercase.(att_info[:definition][!,:id]))
        add_head_category!(att_info,h)
    end
    DDLm_Dictionary(att_info, nspace)
end

"""
DDL2_Dictionary(ds, att_dic::DDL2_Dictionary, dividers)

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
        if has_category(ds, ac, "ddl2") println("We have category $ac") end
        catinfo = get_category(ds, ac, "ddl2")
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

