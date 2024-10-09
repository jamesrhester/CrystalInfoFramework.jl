# **DDLm Dictionaries
#
#
# The following semantics are important for DDLm dictionaries:
# (1) Importation. A DDLm dictionary can import parts of definitions,
# or complete dictionaries in order to describe the whole semantic space
# (2) Parent-child. An object name may be referenced as if it were
# part of the parent category; so if <c> is a child of <p>, and <q> is
# an object in <c> (that is, "_c.q" is the dataname), then "p.q" refers
# to the same item as "c.q" in dREL methods. It is not the case that
# "_p.q" is a defined dataname.  The code here therefore implements only
# the methods needed to find parents and children. 
#
# Namespaces: data names in the dictionary may be assigned to a particular
# namespace.
#
# A reference dictionary may be supplied containing the definitions of the
# DDLm attributes. A default reference dictionary is supplied.

using Printf,Dates

export DDLm_Dictionary
export find_category,get_categories,get_set_categories
export list_aliases
export find_object,find_name,filter_def
export get_single_key_cats
export get_linked_names_in_cat,get_keys_for_cat
export get_linked_name
export get_objs_in_cat
export get_dict_funcs                   #List the functions in the dictionary
export get_parent_category,get_child_categories
export is_set_category,is_loop_category
export get_func,get_func_text,set_func!,has_func,load_func_text
export has_default_methods,remove_methods!
export get_def_meth,get_def_meth_txt,has_def_meth    #Methods for calculating defaults
export get_loop_categories, get_dimensions, get_single_keyname
export get_ultimate_link
export get_dataname_children   #get all datanames this is a parent for
export get_default,lookup_default
export get_dic_name
export get_cat_class
export get_enums          #get all enumerated lists
export get_attribute      #get value of particular attribute for a definition 
export get_dic_namespace
export get_child_categories # all child categories
export is_category
export find_head_category,add_head_category!
export rename_category!, rename_name!   #Rename category and names throughout
export get_julia_type_name,get_dimensions
export conform_capitals!  #Capitalise according to style guide
export add_definition!    #add new definitions
export add_key!           #add a key data name to a category
export check_import_block #inspect an import block

# Editing
export update_dict! #Update dictionary contents
export make_cats_uppercase! #Conform to style guide

# With data
export has_category   # check if a data block has a category
export count_rows     # how many rows in a category in a datablock
export add_child_keys! # add any missing keys
export make_set_loops! # make sure block loops everything
    
# Displaying
import Base.show

"""
A DDLm Dictionary holds information about data names including
executable methods for deriving missing values.
"""
struct DDLm_Dictionary <: AbstractCifDictionary
    block::Dict{Symbol,GroupedDataFrame}
    func_defs::Dict{String,Function}
    func_text::Dict{String,Expr} #unevaluated Julia code
    def_meths::Dict{Tuple,Function}
    def_meths_text::Dict{Tuple,Expr}
    namespace::String
    header_comments::String
    import_dir::String   #for looking at imports later
    cached_imports::Dict{Any,DDLm_Dictionary}
end

"""
    DDLm_Dictionary(c::Cif;ignore_imports=false)

Create a `DDLm_Dictionary` from `c`. `ignore_imports = true` will
ignore any `import` attributes.
"""
DDLm_Dictionary(c::Cif;kwargs...) = begin
    if length(keys(c))!= 1
        error("Error: Cif dictionary has more than one data block")
    end
    return DDLm_Dictionary(first(c).second;header=get_header_comments(c),kwargs...)
end

"""
    DDLm_Dictionary(a::AbstractPath;verbose=false,ignore_imports="None",
    cache_imports=false)

Create a `DDLm_Dictionary` given filename `a`. `verbose = true` will print
extra debugging information during reading.`ignore_imports = :None` will ignore
any `import` attributes. Other options are `:Full` and `:Contents` to ignore
imports with the respective `mode`, and `:all` to ignore all imports.
`cache_imports` will store the contents of imported
files (`Contents` mode only) but will not merge the contents into the
importing definition.

Setting `ignore_imports` to :None (the default) merges all information in
imported files into the dictionary, replacing the `import` attribute.

By default imports are cached, even if they are not
merged. `cache_imports` can be set to `false` to completely ignore any
import attributes.

`cache_imports` is ignored if `ignore_imports` is :None.

If a non-absolute location for imported dictionaries is specified, they are
searched for relative to the same directory as the importing dictionary,
unless `import_dir` is specified, in which case the search is relative to
that directory.

"""
DDLm_Dictionary(a::AbstractPath;verbose=false,kwargs...) = begin
    c = Cif(a,verbose=verbose,native=true) #Native to catch header comments
    DDLm_Dictionary(c;kwargs...)
end

DDLm_Dictionary(a::String;kwargs...) = begin
    DDLm_Dictionary(Path(a);kwargs...)
end

DDLm_Dictionary(b::CifBlock;ignore_imports=:None,header="",cache_imports=true,import_dir="") = begin
    all_dict_info = Dict{Symbol,DataFrame}()
    # Namespace
    nspace = get(b,"_dictionary.namespace",[""])[]
    title = lowercase(b["_dictionary.title"][])
    # loop over all blocks, storing information
    defs = get_frames(b)
    bnames = keys(defs)
    for k in bnames
        # process loops
        defid = lowercase(get(defs[k],"_definition.id",[k])[])
        loops = get_loop_names(defs[k])
        for one_loop in loops
            new_info = get_loop(defs[k],first(one_loop))
            update_dict!(all_dict_info,new_info,CaselessString("master_id"),defid)
        end
        # process unlooped
        unlooped = [x for x in keys(defs[k]) if !(x in Iterators.flatten(loops))]
        cats = unique([split(x,'.')[1][2:end] for x in unlooped])
        #println("Cats for $k: $cats")
        for one_cat in cats
            dnames = filter(x-> split(x,'.')[1][2:end] == one_cat,unlooped)
            new_vals = (defs[k][x][] for x in dnames)
            @assert length(new_vals)>0
            update_row!(all_dict_info,Dict(zip(dnames,new_vals)),CaselessString("master_id"),defid)
        end
    end
    # and now store information in the enclosing block
    loops = get_loop_names(b)
    for one_loop in loops
        new_info = get_loop(b,first(one_loop))
        update_dict!(all_dict_info,new_info,CaselessString("master_id"),title)
    end
    # process unlooped
    unlooped = [x for x in keys(b) if !(x in Iterators.flatten(loops))]
    cats = unique([split(x,'.')[1][2:end] for x in unlooped])
    for one_cat in cats
        dnames = filter(x-> split(x,'.')[1][2:end] == one_cat,unlooped)
        new_vals = (b[x][] for x in dnames)
        update_row!(all_dict_info,Dict(zip(dnames,new_vals)),CaselessString("master_id"),title)
    end
    cache = Dict()
    # process imports
    if import_dir == "" import_dir = dirname(b.original_file) end
    if cache_imports || ignore_imports != :All
        cache = import_cache(all_dict_info,import_dir)
    end
    if ignore_imports != :All
        resolve_imports!(all_dict_info,import_dir,cache, ignore_imports)
    end
    # Apply default values if not a template dictionary
    if all_dict_info[:dictionary][!,:class][] != "Template"
        enter_defaults(all_dict_info)
    end
    if all_dict_info[:dictionary].class[] == "Reference"
        extra_reference!(all_dict_info)
    end
    DDLm_Dictionary(all_dict_info,nspace,header=header,origin=import_dir,
                    imports=cache)
end

"""
    DDLm_Dictionary(attr_dict::Dict{Symbol,DataFrame},nspace,header="",origin="")

The symbol keys in `attr_dict` are DDLm attribute categories, 
and the columns in the indexed `DataFrame`s are the object_ids 
of the DDLm attributes of that category. `header` are optional comments
to be output at the top of the dictionary.
"""
DDLm_Dictionary(attr_dict::Dict{Symbol,DataFrame},nspace;header="",origin="",imports=Dict()) = begin
    # group for efficiency
    gdf = Dict{Symbol,GroupedDataFrame}()
    for k in keys(attr_dict)
        gdf[k] = groupby(attr_dict[k],:master_id)
    end
    DDLm_Dictionary(gdf,Dict(),Dict(),Dict(),Dict(),nspace,header,origin,imports)
end

"""
    keys(d::DDLm_Dictionary)

Return a list of datanames defined by the dictionary, including
any aliases.
"""
keys(d::DDLm_Dictionary) = begin
    native = lowercase.(unique(first.(Iterators.flatten(values.(keys(v) for v in values(d.block))))))
    extra = []
    if haskey(d.block,:alias)
        extra = lowercase.(parent(d.block[:alias])[!,:definition_id])
    end
    return Iterators.flatten((native,extra))
end

haskey(d::DDLm_Dictionary,k::AbstractString) = lowercase(k) in keys(d)

"""
    getindex(d::DDLm_Dictionary,k)

d[k] returns the  definition for data name `k` as a `Dict{Symbol,DataFrame}`
where `Symbol` is the attribute category (e.g. `:name`).
"""
getindex(d::DDLm_Dictionary,k) = begin
    canonical_name = find_name(d,k)
    return filter_on_name(d.block,canonical_name)
end

# If a symbol is passed we access the block directly.
getindex(d::DDLm_Dictionary,k::Symbol) = parent(getindex(d.block,k)) #not a grouped data frame
get(d::DDLm_Dictionary,k::Symbol,default) = parent(get(d.block,k,default))

# Allow access to an arbitrary attribute within a definition
"""
    get_attribute(d::DDLm_Dictionary,defname,attname::String)

Return the value of `attname` in definition `defname` of dictionary `d`. Will return 
`missing` if absent.
"""
get_attribute(d::DDLm_Dictionary,defname,attname::String) = begin
    all_attrs = d[defname]
    tab,obj = split(attname,'.')
    tab = Symbol(tab[2:end])
    if !haskey(all_attrs,tab) return missing end
    target_tab = all_attrs[tab]
    if !(obj in names(target_tab)) return missing end
    if length(target_tab[!,obj]) == 0 return missing end
    return target_tab[!,obj]
end

"""
delete!(d::DDLm_Dictionary,k::String)

Remove all information from `d` associated with dataname `k`
"""
delete!(d::DDLm_Dictionary,k::String) = begin
    canonical_name = find_name(d,k)
    for cat in keys(d.block)
        delete!(parent(d.block[cat]),parent(d.block[cat])[!,:master_id] .== canonical_name)
        # regroup
        d.block[cat] = groupby(parent(d.block[cat]),:master_id)
    end
end

"""
    filter_def((cat,obj),value,d::DDLm_Dictionary)

Return a dictionary containing only those definitions in `d` for which
attribute given by `_cat.obj` takes `value`.  If an attribute is
looped, the definition is included if at least one of the values is
`value`. `cat` and `obj` should be given as symbols.

Example:

filter_def((:type,:purpose),"Measurand",d)

will return a dictionary containing only "Measurand" data items from `d`.
"""
filter_def(catobj,val,d::DDLm_Dictionary) = begin
    cat,obj = catobj
    target_cat = get(d,cat,DataFrame())
    def_names = []
    if nrow(target_cat) != 0 && obj in propertynames(target_cat)
        all_hits = target_cat[target_cat[!,obj] .== val,:]
        def_names = all_hits.master_id
    end
    # filter on names
    info_dict = Dict{Symbol,DataFrame}()
    for cat in keys(d.block)   #use symbols to access master block
        info_dict[cat] = d[cat][in.(d[cat][!,:master_id], Ref(def_names)),:]
    end
    # fix up with same dictionary header
    info_dict[:dictionary] = d[:dictionary]
    hc = find_head_category(d)
    add_head_category!(info_dict,hc)
    return DDLm_Dictionary(info_dict,d.namespace)
end

# `k` is assumed to be already lower case

filter_on_name(d::Dict{Symbol,GroupedDataFrame},k) = begin
    info_dict = Dict{Symbol,DataFrame}()
    trial = DataFrame()
    for cat in keys(d)
        try
            trial = d[cat][(master_id = k,)]
        catch KeyError
            trial = DataFrame()
        end
        # find columns that are not all missing
        keep_cols = filter(x-> any(y->!ismissing(y),trial[!,x]),propertynames(trial))
        newdf = DataFrame()
        for k in keep_cols
            newdf[!,k] = trial[!,k]
        end
        info_dict[cat] = newdf
        #select!(info_dict[cat],keep_cols...)
    end
    return info_dict
end

filter_on_name(d::Dict{Symbol,DataFrame},k) = begin
    info_dict = Dict{Symbol,DataFrame}()
    for cat in keys(d)
        info_dict[cat] = d[cat][d[cat][!,:master_id] .== k,:]
    end
    return info_dict
end

get_dic_name(d::DDLm_Dictionary) = parent(d[:dictionary])[!,:title][]

"""
    get_dic_namespace(d::DDLm_Dictionary)

Return the namespace declared by the dictionary, or
`ddlm` if none present.
"""
get_dic_namespace(d::DDLm_Dictionary) = begin
    if :namespace in propertynames(d[:dictionary])
        d[:dictionary][!,:namespace][]
    else
        "ddlm"
    end
end

"""
    list_aliases(d::DDLm_Dictionary,name;include_self=false)

List aliases of `name` listed in `d`. If not `include_self`, remove
`name` from the returned list.
"""
list_aliases(d::DDLm_Dictionary,name;include_self=false) = begin
    result = d[name][:definition][:,:id]
    alias_block = get(d[name],:alias,nothing)
    if !isnothing(alias_block) && nrow(d[name][:alias]) > 0
        append!(result, alias_block[!,:definition_id])
    end
    if !include_self filter!(!isequal(name),result) end
    return result
end


"""
    find_name(d::DDLm_Dictionary,name)

Find the canonical name for `name` in `d`. If `name` is not
present, return `name` unchanged. If accessed in cat/obj format, search also child
categories. Note that the head category may not have a category associated with it.
If `name` is the dictionary title it is returned as is.
"""
find_name(d::DDLm_Dictionary,name) =  begin
    lname = lowercase(name)
    if lname == lowercase(d[:dictionary].title[]) return lname end
    # A template etc. dictionary has no defs
    if !haskey(d.block,:definition) return lname end
    if !(:id in propertynames(d[:definition])) return lname end
    if lname in lowercase.(d[:definition][!,:id]) return lname end
    if !haskey(d.block,:alias) return lname end
    potentials = d[:alias][lowercase.(d[:alias][!,:definition_id]) .== lname,:master_id]
    if length(potentials) == 1 return potentials[] end
    throw(KeyError(name))
end

"""
    find_name(d::DDLm_Dictionary,cat,obj)

Find the canonical name referenced by `cat.obj` in `d`, searching also child
categories according to DDLm semantics. Note that the head category may not 
have a category associated with it.
"""
find_name(d::DDLm_Dictionary, cat, obj) = begin
    cat = String(cat)
    obj = String(obj)
    catcol = d[:name][!,:category_id]
    selector = map(x-> !isnothing(x) && lowercase(x) == lowercase(cat),catcol)
    pname = d[:name][selector .& (lowercase.(d[:name][!,:object_id]) .== lowercase(obj)),:master_id]
    if length(pname) == 1 return pname[]
    elseif length(pname) > 1
        throw(error("More than one name satisfies $cat.$obj: $pname"))
    end
    for c in get_child_categories(d,cat)
        pname = d[:name][(lowercase.(d[:name][!,:category_id]) .== lowercase(c)) .& (lowercase.(d[:name][!,:object_id]) .== lowercase(obj)),:master_id]
        if length(pname) == 1 return pname[]
        elseif length(pname) > 1
            throw(error("More than one name satisfies $c.$obj: $pname"))
        end
    end
    throw(KeyError("$cat/$obj"))
end

find_name(d::DDLm_Dictionary, cat::Symbol, obj::Symbol) = begin
    find_name(d, String(cat), String(obj))
end

"""
    find_category(d::DDLm_Dictionary,dataname)

Find the category of `dataname` by looking up `d`.
"""
find_category(d::DDLm_Dictionary,dataname) = lowercase(d[dataname][:name][!,:category_id][])

"""
    find_object(d::DDLm_Dictionary,dataname)

Find the `object_id` of `dataname` by looking up `d`.
"""
find_object(d::DDLm_Dictionary,dataname) = lowercase(d[dataname][:name][!,:object_id][])

"""
    is_category(d::DDLm_Dictionary,name)

Return true if `name` is a category according to `d`.
"""
is_category(d::DDLm_Dictionary,name) = begin
    definfo = d[name][:definition]
    :scope in propertynames(definfo) ? definfo[!,:scope][] == "Category" : false
end

"""
    get_categories(d::DDLm_Dictionary, referred=false)

List all categories defined in DDLm Dictionary `d`. If `referred` is `true`, categories
for which data names are defined, but no category is defined, are also included.
"""
get_categories(d::Union{DDLm_Dictionary,Dict{Symbol,DataFrame}}; referred = false) = begin
    defed_cats = lowercase.(d[:definition][d[:definition][!,:scope] .== "Category",:id])
    if !referred return defed_cats end
    more_cats = unique!(lowercase.(d[:name].category_id))
    # remove dictionary name if that is referred to by the Head category
    head_cat = find_head_category(d)
    up_cat = get_parent_category(d, head_cat)
    drop = head_cat == up_cat ? [] : [up_cat]
    return setdiff(union(defed_cats, more_cats), drop)
end

"""
    get_cat_class(d,catname)

The DDLm category class of `catname` as defined in DDLm Dictionary `d`
"""
get_cat_class(d::DDLm_Dictionary,catname) = :class in propertynames(d[catname][:definition]) ? d[catname][:definition][!,:class][] : "Datum"

"""
    is_set_category(d::DDLm_Dictionary,catname)

Return true if `catname` is declared as a Set category. If `d` is a `Reference` dictionary defining
DDLm attributes themselves, only the `dictionary` category is a Set category.
"""
is_set_category(d::DDLm_Dictionary,catname) = begin
    cat_decl = get_cat_class(d,catname)
    dic_type = d[:dictionary].class[]
    if dic_type != "Reference" && cat_decl == "Set" return true end
    if dic_type == "Reference" && catname == "dictionary" return true end
    return false
end

"""
    is_loop_category(d::DDLm_Dictionary,catname)

Return true if `catname` is declared as a Loop category. For
`Reference` dictionaries describing the DDLm attributes themselves,
all categories except `dictionary` are treated as Loop categories.
"""
is_loop_category(d::DDLm_Dictionary,catname) = begin
    cat_decl = get_cat_class(d,catname)
    dic_type = d[:dictionary].class[]
    if dic_type == "Reference" && catname == "dictionary" return false end
    if dic_type == "Reference" && cat_decl == "Set" return true end
    return cat_decl == "Loop"
end

"""
    get_objs_in_cat(d::DDLm_Dictionary,catname)

List all object_ids defined for `catname` in `d`.
"""
get_objs_in_cat(d::DDLm_Dictionary,cat) = begin
    temp = d[:name][!,:category_id]
    selector = map(x-> !isnothing(x) && lowercase(x) == lowercase(cat),temp)
    lowercase.(d[:name][selector,:object_id])
end

"""
    get_keys_for_cat(d::DDLm_Dictionary,cat;aliases=false)

List all category key data names for `cat` listed in `d`. If `aliases`, include alternative names
for the key data names.
"""
get_keys_for_cat(d::DDLm_Dictionary, cat;aliases=false) = begin
    loop_keys = lowercase.(d[:category_key][lowercase.(d[:category_key][!,:master_id]) .== lowercase(cat),:name])
    key_aliases = String[]
    if aliases
        for k in loop_keys
            append!(key_aliases,list_aliases(d,k))
        end
    end
    append!(key_aliases,loop_keys)
    return key_aliases
end

get_keys_for_cat(d::DDLm_Dictionary, cat::Symbol; kwargs...) = begin
    get_keys_for_cat(d, String(cat); kwargs...)
end

"""
    get_linked_names_in_cat(d::DDLm_Dictionary,cat)

List all data names in `cat` that are children of other data names.
"""
get_linked_names_in_cat(d::DDLm_Dictionary,cat) = begin
    names = [n for n in get_names_in_cat(d,cat) if d[n][:name][!,:linked_item_id][] != nothing]
    [n for n in names if d[n][:type][!,:purpose][] != "SU"]
end

"""
    get_linked_name(d::DDLm_Dictionary,name) = begin

Return any name linked to `name` that is not a SU, returning `name` if none found
"""
get_linked_name(d::DDLm_Dictionary,name) = begin
    info = d[name][:name]
    poss = :linked_item_id in propertynames(info) ? info.linked_item_id[] : name
    if isnothing(poss) return name end
    link_type = :purpose in propertynames(d[name][:type]) ? d[name][:type].purpose[] : "Datum"
    if link_type != "SU" return poss end
    return name
end

"""
    get_set_categories(d::DDLm_Dictionary)

Return all categories that may only have one row in a single data block. 
For Reference dictionaries defining DDLm attributes, only `dictionary` 
is considered a Set category.
"""
get_set_categories(d::DDLm_Dictionary) = begin
    if d[:dictionary].class[] == "Instance"
        lowercase.(d[:definition][d[:definition][!,:class] .== "Set",:id])
    else
        ["dictionary"]
    end
end

"""
    get_loop_categories(d::DDLm_Dictionary)

Return all categories that may have multiple rows in a single data block. For 
Reference dictionaries defining DDLm attributes, only `dictionary` is not a Loop category.
"""
get_loop_categories(d::DDLm_Dictionary) = begin
    if d[:dictionary].class[] == "Instance"
        lowercase.(d[:definition][d[:definition][!,:class] .== "Loop",:id])
    else
        lowercase.(d[:definition][d[:definition][!,:id] .!= "dictionary",:id])
    end
end

"""
    get_toplevel_cats(d::DDL2_Dictionary)

Return a list of category names that appear outside the definition blocks.
Typically these are lists of types, units, groups and methods.
"""
get_toplevel_cats(d::DDLm_Dictionary) = begin
    w = d[get_dic_name(d)]
    [k for k in keys(w) if nrow(w[k])>0]
end

# ***Dictionary functions***

"""
    get_dict_funcs(d::DDLm_Dictionary)

Return `(func_catname, all_funcs)`, where `func_catname` is the single category of class `Functions`
in `d`, and `all_funcs` is a list of all object_ids for that category.
"""
get_dict_funcs(d::DDLm_Dictionary) = begin
    func_cat = d[:definition][d[:definition][!,:class] .== "Functions",:id]
    func_catname = nothing
    if length(func_cat) > 0
        func_catname = lowercase(d[func_cat[]][:name][!,:object_id][])
        all_funcs = get_objs_in_cat(d,func_catname)
    else
        all_funcs = []
    end
    return func_catname,all_funcs
end

"""
    get_parent_category(d::DDLm_Dictionary,child; default_cat = nothing)

Find the parent category of `child` according to `d`. `default_cat` is the
category to use if no parent is specified (for example, the category information
is contained in a dictionary that is not imported).
"""
get_parent_category(d::DDLm_Dictionary,child; default_cat = nothing) = begin
    try
        lowercase(d[child][:name][!,:category_id][])
    catch
        if isnothing(default_cat)
            return child
        else
            return default_cat
        end
    end
end

"""
    is_parent(d::DDLm_Dictionary,parent,child)

Returns true if `parent` is a direct or indirect parent of `child`
"""

is_parent(d::DDLm_Dictionary,parent,child) = begin
    p = get_parent_category(d,child)
    while p != parent
        q = get_parent_category(d,p)
        if q == p
            break
        else
            p = q
        end
    end
    return p == parent
end


"""
    get_child_categories(d::DDLm_Dictionary,parent)

Find the child categories of `parent` according to `d`.
TODO: more than one level down.
"""
get_child_categories(d::DDLm_Dictionary, parent) = begin
    [c for c in get_categories(d) if get_parent_category(d,c) == lowercase(parent)]
end

"""
    get_single_keyname(d::DDLm_Dictionary,c)

Return the `object_id` of the single key data name of category `c`.
An error is raised if there is not precisely one key data name for `c`.
"""
get_single_keyname(d::DDLm_Dictionary,c) = begin
    keys = get_keys_for_cat(d,c)
    if length(keys) == 0
        error("Category $c has no keys defined")
    end
    if length(keys) > 1
        error("Category $c has more than one key")
    end
    obj = keys[]
    d[obj][:name][!,:object_id][]
end

"""
    get_single_key_cats(d::DDLm_Dictionary)

Return a list (category, keyname) for all categories that have
a single key, where that key is not a child key of another
category. This latter case corresponds to a split single
category.
"""
get_single_key_cats(d::DDLm_Dictionary) = begin
    candidates = get_categories(d)
    k = [(c,get_keys_for_cat(d,c)[]) for c in candidates if length(get_keys_for_cat(d,c)) == 1]
    filter!(k) do x
        linkval = d[x[2]][:name][!,:linked_item_id][]
        linkval == nothing || linkval == x[2]
    end
end

"""
    get_enums(d::DDLm_Dictionary)

Return all items defined in `d` that take enumerated values, together
with the list of values as a dictionary.
"""

get_enums(d::DDLm_Dictionary) = begin
    res = Dict{String,Array{Union{Nothing,String},1}}()
    for k in keys(d)
        v = d[k]
        if haskey(v,:enumeration_set) && nrow(v[:enumeration_set])>0
            res[k] = v[:enumeration_set].state
        end
    end
    return res
end

"""
    get_ultimate_link(d::DDLm_Dictionary,dataname::AbstractString)

Find the ultimately-linked dataname for `dataname`, returning `dataname`
if there are no links.
"""
get_ultimate_link(d::DDLm_Dictionary, dataname::AbstractString) = begin
    if haskey(d,dataname)
        #println("Searching for ultimate value of $dataname")
        if :linked_item_id in propertynames(d[dataname][:name])
            linkval = d[dataname][:name][!,:linked_item_id][]
            if linkval != dataname && linkval != nothing
                return get_ultimate_link(d,linkval)
            end
        end
    end
    return dataname
end

"""
    get_dataname_children(d::DDLm_Dictionary, dataname::AbstractString)

Return a list of all datanames that have `dataname` as a direct or indirect
parent. `dataname` is the first entry in the list.
"""
get_dataname_children(d::DDLm_Dictionary, dataname::AbstractString) = begin
    
    full_list = [dataname]
    next_level = full_list
    while next_level != []
        new_level = []
        for nl in next_level
            selector = map( x -> !isnothing(x) && x == nl, d[:name][!,:linked_item_id])
            append!(new_level, d[:name][selector,:master_id])
        end
        append!(full_list, new_level)
        next_level = new_level
    end

    return full_list
end

"""
    get_default(d::DDLm_Dictionary,s)

Return the default value for `s` or `missing` if none defined. 
"""
get_default(d::DDLm_Dictionary,s) = begin
    info = d[s][:enumeration]
    if :default in propertynames(info)
        return info[!,:default][]
    end
    return missing
end

#   ***Default lookup 
#
# A default value may be tabulated, and some other value in the
# current packet is used to index into the table. `cp` is an
# object with symbolic properties corresponding to the
# items in a category.
#

"""
    lookup_default(dict::DDLm_Dictionary,dataname::String,cp)

Index into any default lookup table defined in `dict` for `dataname` using an index value from
`cp`. `cp` is any object with a property name as specified by `def_index_id` in the definition of 
`dataname` such that `cp.<def_index_id>` returns a single value
"""
lookup_default(dict::DDLm_Dictionary,dataname::String,cp) = begin
    definition = dict[dataname][:enumeration]
    index_name = :def_index_id in propertynames(definition) ? definition[!,:def_index_id][] : missing
    if ismissing(index_name) return missing end
    object_name = find_object(dict,index_name)
    # Note non-deriving form of getproperty
    # println("Looking for $object_name in $(getfield(getfield(cp,:source_cat),:name))")
    current_val = getproperty(cp,Symbol(object_name))
    @debug "Indexing $dataname using $current_val to get"
    # Now index into the information. ddl.dic states that this is of type 'Code'
    # so we apply the CaselessString constructor
    indexlist = CaselessString.(dict[dataname][:enumeration_default][!,:index])
    pos = indexin([current_val],indexlist)
    if pos[1] == nothing return missing end
    return dict[dataname][:enumeration_default][!,:value][pos[1]]
end

# ***Methods for setting and retrieving evaluated functions

"""
    load_func_text(dict::DDLm_Dictionary,dataname::String,meth_type::String)

Return the text of a method found in the definition of `dataname` in `dict`. The
method must have purpose `meth_type`.
"""
load_func_text(dict::DDLm_Dictionary,dataname::String,meth_type::String) =  begin
    full_def = dict[dataname]
    func_text = full_def[:method]
    if size(func_text,2) == 0   #nothing
        return ""
    end
    # TODO: allow multiple methods
    eval_meths = func_text[func_text[!,:purpose] .== meth_type,:]
    @debug "Meth size for $dataname is $(size(eval_meths))"
    if size(eval_meths,1) == 0
        return ""
    end
    eval_meth = eval_meths[!,:expression][]
end

"""
    remove_methods!(dict::DDLm_Dictionary)

Remove all methods from the `dict`. This will stop any
further automatic derivation taking place.
"""
remove_methods!(dict::DDLm_Dictionary) = begin
    dict.block[:method] = groupby(DataFrame([[]],[:master_id]),:master_id)
    for k in keys(dict.func_defs)
        delete!(dict.func_defs, k)
        delete!(dict.func_text, k)
    end
end

"""
    as_data(d::DDLm_Dictionary)

Create an object `o` from `d` such that `o[attribute]` provides data for `attribute`
as an array of Strings. 
"""
as_data(d::DDLm_Dictionary) = begin
    output = Dict{String,Any}()
    for c in keys(d.block)
        for o in propertynames(parent(d.block[c]))
            output["_$c.$o"] = parent(d.block[c])[!,o]
        end
    end
    return output
end

"""
    as_jdict(d::DDLm_Dictionary)

Return a Julia dictionary corresponding to the attribute categories
held in `d`. This effectively recovers the `attr_dict` input to the 
DDLm_Dictionary constructor. The underlying data are copied so can
be mutated without affecting `d`.
"""
as_jdict(d::DDLm_Dictionary) = begin
    output = Dict{Symbol,DataFrame}()
    for (c,b) in d.block
        output[c] = copy(parent(b))
    end
    return output
end

"""
    set_func!(d::DDLm_Dictionary,func_name::String,func_text::Expr,func_code)

Store compiled code `func_code` created from `func_text` under `func_name` in `d`.
"""
set_func!(d::DDLm_Dictionary,func_name::String,func_text::Expr,func_code) = begin
    d.func_defs[func_name] = func_code
    d.func_text[func_name] = func_text
end

"""
    get_func(d::DDLm_Dictionary,func_name::String)

Retrieve the compiled code stored for `func_name` in `d`.
"""
get_func(d::DDLm_Dictionary,func_name::String) = d.func_defs[func_name]

"""
    get_func_text(d::DDLm_Dictionary,func_name::String)

Retrieve the text stored for `func_name` in `d`.
"""
get_func_text(d::DDLm_Dictionary,func_name::String) = d.func_text[func_name]

"""
    has_func(d::DDLm_Dictionary,func_name::String)

Return `true` if code is available for `func_name` in `d`
"""
has_func(d::DDLm_Dictionary,func_name::String) = begin
    try
        d.func_defs[func_name]
    catch KeyError
        return false
    end
    return true
end

# Methods for setting and retrieving definition functions
"""
    has_default_methods(d::DDLm_Dictionary)

Return true if `d` contains methods for calculating default values
"""
has_default_methods(d::DDLm_Dictionary) = true

"""
    has_def_meth(d::DDLm_Dictionary,func_name::String,ddlm_attr::String)

Return true if `d` contains compiled code for calculating default values of attribute `ddlm_attr` in
data name definition `func_name`
"""
has_def_meth(d::DDLm_Dictionary,func_name::String,ddlm_attr::String) = haskey(d.def_meths,(func_name,ddlm_attr))

"""
    get_def_meth(d::DDLm_Dictionary,func_name::String,ddlm_attr::String)

Return compiled code for calculating default values of attribute `ddlm_attr` in
data name definition `func_name` contained in dictionary `d`.
"""
get_def_meth(d::DDLm_Dictionary,func_name::String,ddlm_attr::String) = d.def_meths[(func_name,ddlm_attr)]

"""
    get_def_meth_txt(d::DDLm_Dictionary,func_name::String,ddlm_attr::String)

Return text of code for calculating default values of attribute `ddlm_attr` in
data name definition `func_name` contained in dictionary `d`.
"""
get_def_meth_txt(d::DDLm_Dictionary,func_name::String,ddlm_attr::String) = d.def_meths_text[(func_name,ddlm_attr)]

"""
    set_func!(d::DDLm_Dictionary,func_name::String,ddlm_attr::String,func_text::Expr,func_code)

Store compiled code `func_code` for calculating the default value of `ddlm_attr` for definition
`func_name`. The uncompiled version is provided in `func_text`.
"""
set_func!(d::DDLm_Dictionary,func_name::String,ddlm_attr::String,func_text::Expr,func_code) = begin
    d.def_meths[(func_name,ddlm_attr)] = func_code
    d.def_meths_text[(func_name,ddlm_attr)] = func_text
end

"""
    get_parent_name(d::DDLm_Dictionary,name)

Get the category to which `name` belongs.
"""
get_parent_name(d::DDLm_Dictionary,name) = begin
    d[name][:name][!,:category_id][]
end

#== Dictionary updating

Helper functions for building dictionaries. In general access to
the unsorted tables is necessary.

==#

"""
    update_dict!(d::DDLm_Dictionary,dname,attr,old_val,new_val;all=true)

Update dictionary `d`, making the value of the `old_val` item of
attribute `attr` in the definition for `dname` equal to `new_val`.
`old_val` must exist otherwise an error is raised. If more than one
entry for `attr` equals `old_val` and `all` is true, all values are 
changed, otherwise only the first value is changed. If no values were
changed, `false` is returned, otherwise `true`.
"""
update_dict!(d::DDLm_Dictionary,dname,attr,old_val,new_val;all=true) = begin
    tablename,objname = split(attr,'.')
    tablename = Symbol(tablename[2:end])
    objname = Symbol(objname)
    for_update = d[dname][tablename]
    updated  = false
    for one_row in eachrow(for_update)
        if getproperty(one_row,objname) == old_val
            setproperty!(one_row,objname,new_val)
            updated = true
            if !all break end
        end
    end
    if attr == "_definition.id"   # the whole identity changes!
        new_val = lowercase(new_val)
        ldname = lowercase(dname)
        for (t,v) in d.block
            for one_row in eachrow(parent(v))
                if one_row.master_id == ldname
                    one_row.master_id = new_val
                end
            end
        end
        # and resort!
        for t in keys(d.block)
            d.block[t] = groupby(parent(d.block[t]),:master_id)
        end
    end

    return updated
end

"""
If there is only one value, or none, for an attribute there is no need to specify the
value it is replacing.
"""
update_dict!(d::DDLm_Dictionary,dname,attr,new_val) = begin
    old_val = get_attribute(d,dname,attr)
    if ismissing(old_val)
        dcat,dobj = split(attr,".")
        dcat = Symbol(dcat[2:end])
        dobj = Symbol(dobj)
        underlying = as_jdict(d)
        if !haskey(underlying,dcat)
            underlying[dcat] = DataFrame(:master_id=>[lowercase(dname)])
        end
        if !(dobj in propertynames(underlying[dcat]))
            insertcols!(underlying[dcat],(dobj=>missing))
        end
        
        # Is there a unique row for us?

        check = filter(x->x.master_id == lowercase(dname),underlying[dcat],view=:true)
        if size(check,1) == 1
            check[!,dobj] = [new_val]
        elseif size(check,1) == 0
            @debug "Updating $dname $dcat.$dobj to $new_val"
            push!(underlying[dcat],Dict(:master_id=>lowercase(dname),
                                        dobj => new_val),
                  cols=:subset)
        else
            throw(error("Ambiguous row for updating $attr in $dname"))
        end
        d.block[dcat] = groupby(underlying[dcat],:master_id)
        return d
    elseif length(old_val) != 1
        throw(error("Cannot replace a value for $dname/$attr (ambiguous)"))
    end
    return update_dict!(d,dname,attr,old_val[],new_val)
end

"""

Update the appropriate table of `all_dict_info` with
the contents of `new_info`, filling in implicit values
with column `extra_name` with value `extra_value`
"""
update_dict!(all_dict_info,new_info,extra_name,extra_value) = begin
    tablename = Symbol(split(String(first(names(new_info))),'.')[1][2:end])
    rename!(x-> Symbol(split(String(x),'.')[end]),new_info)
    if !haskey(all_dict_info,tablename)
        all_dict_info[tablename] = DataFrame()
    end
    new_info[!,Symbol(extra_name)] = fill(extra_value,nrow(new_info))
    all_dict_info[tablename] = vcat(all_dict_info[tablename],new_info,cols=:union)
end

update_row!(all_dict_info,new_vals,extra_name,extra_value) = begin
    catname = Symbol(split(first(keys(new_vals)),'.')[1][2:end])
    if !haskey(all_dict_info,catname)
        all_dict_info[catname] = DataFrame()
    end
    final_vals = Dict{Symbol,Any}((Symbol(split(x.first,'.')[end]),[x.second]) for x in new_vals)
    final_vals[Symbol(extra_name)] = extra_value
    #push!(all_dict_info[catname],final_vals,cols=:union) dataframes 0.21
    all_dict_info[catname] = vcat(all_dict_info[catname],DataFrame(final_vals),cols=:union)
end

"""
    add_definition!(all_dict_info::Dict{Symbol,DataFrame},new_def)

Update dictionary information `all_dict_info` with the contents of `new_def`
"""
add_definition!(all_dict_info::Dict{Symbol,DataFrame},new_def::Dict{Symbol,DataFrame}) = begin
    if !haskey(new_def,:definition)
        throw(error("Cannot update definition without data name: given $new_def"))
    end
    defname = lowercase(new_def[:definition].id[])
    for (k,df) in new_def
        if !haskey(all_dict_info,k)
            all_dict_info[k] = DataFrame()
        end
        df[!,:master_id] = fill(defname,nrow(df))
        all_dict_info[k] = vcat(all_dict_info[k],df,cols=:union)
    end
    return all_dict_info
end

"""
    add_definition!(d::DDLm_Dictionary,new_def)

Update DDLm Dictionary `d` with the contents of `new_def`.
"""
add_definition!(d::DDLm_Dictionary,new_def) = begin
    underlying = as_jdict(d)
    updated = add_definition!(underlying,new_def)
    # Apply default values if not a template dictionary
    if underlying[:dictionary][!,:class][] != "Template"
        enter_defaults(underlying)
    end
    for t in keys(updated)         #re-sort
        d.block[t] = groupby(updated[t],:master_id)
    end
    return d
end

"""
    add_key!(ddlm_dict,key_name)

Add an additional key data name `key_name` to dictionary `ddlm_dict`. `key_name` should
have the form `_<cat>.<obj>`
"""
add_key!(ddlm_dict::DDLm_Dictionary,key_name) = begin
    cat,obj = split(key_name,".")
    cat = cat[2:end]
    if !haskey(ddlm_dict,cat)
        throw(error("Category $cat does not exist"))
    end
    if haskey(ddlm_dict[cat],:category_key) && key_name in ddlm_dict[cat][:category_key].name
        @debug "Adding key that already exists to $cat: $key_name"
        return
    end
    underlying = as_jdict(ddlm_dict)
    if haskey(underlying,:category_key)
        push!(underlying[:category_key],Dict(:master_id=>lowercase(cat),
                                         :name=>key_name,))
    else
        underlying[:category_key] = DataFrame(:master_id=>[lowercase(cat)],
                                              :name=>[key_name])
    end
    ddlm_dict.block[:category_key] = groupby(underlying[:category_key],:master_id)
    # register the update
    include_date(ddlm_dict,cat)
end

"""
    Set _definition.update to today
"""
include_date(ddlm_dict,dataname) = begin
    update_dict!(ddlm_dict,dataname,"_definition.update","$(today())")
end

"""
    rename_category!(d::DDLm_Dictionary,old,new)

Change all appearances of category `old` to `new`. This includes renaming datanames
and changing `_name.category_id` attributes. It cannot change references to datanames
in definition text or dREL methods (yet).
"""
rename_category!(d::DDLm_Dictionary,old,new) = begin
    if !is_category(d,old) return end
    # Collect information
    dnames = get_names_in_cat(d,old)
    # Change category definition itself
    update_dict!(d,old,"_name.object_id",new)
    update_dict!(d,old,"_definition.id",new)
    for one_name in dnames
        obj = d[one_name][:name][!,:object_id][]
        newname = "_"*new*"."*obj
        update_dict!(d,one_name,"_name.category_id",new)
        rename_name!(d,one_name,newname)
    end
    # Reparent categories
    d[:name][:,:category_id] = map(x-> !ismissing(x) && lowercase(x) == lowercase(old) ? new : x, d[:name][!,:category_id])
end

"""
    rename_name!(d::DDLm_Dictionary,old,new)

Change dataname `old` to `new`. The category and object are not touched. All references
to this name in `d` are adjusted to the new name. To update the data name due to changing
the category, use `rename_category!` 
"""
rename_name!(d::DDLm_Dictionary,old,new) = begin
    if is_category(d,old) return end
    update_dict!(d,old,"_definition.id",new)
    for (c,o) in ((:name,:linked_item_id),(:alias,:definition_id),(:category_key,:name),
                  (:enumeration,:def_index_id))
        if !haskey(d.block,c) continue end
        if !(o in propertynames(parent(d.block[c]))) continue end
        d[c][:,o] = map(x-> !ismissing(x) && !isnothing(x) && lowercase(x) == lowercase(old) ? new : x , d[c][!,o])
    end
end

"""
    find_head_category(df::DataFrame)

Find the category that is at the top of the category tree by following object->category
links.
"""
find_head_category(df::DataFrame) = begin
    # get first and follow it up
    old_cat = lowercase(df.category_id[1])
    even_older_cat = old_cat
    new_cat = old_cat
    while true
        new_cat = lowercase.(df[lowercase.(df[!,:object_id]) .== old_cat,:category_id])
        if length(new_cat) == 0 #old_cat is not a thing
            new_cat = even_older_cat
            break
        end
        if new_cat[] == old_cat #pointing to self, that'll do
            new_cat = new_cat[]
            break
        end
        @debug "$old_cat -> $new_cat"
        even_older_cat = old_cat
        old_cat = new_cat[]
    end
    #println("head category is $old_cat")
    return new_cat
end

"""
    find_head_category(df::Dict{Symbol,DataFrame})

Find the category that is at the top of the category tree by searching for a
`Head` category in `df[:definition]`, or else following `category->object`
links in `df[:name]`
"""
find_head_category(df::Dict) = begin
    if haskey(df,:definition)
        explicit_head = df[:definition][df[:definition].class .== "Head",:master_id]
        if length(explicit_head) == 1
            return explicit_head[]
        elseif length(explicit_head) > 1
            @warn "Warning, more than one head category" explicit_head
        end
    end
    find_head_category(df[:name])
end

"""
    find_head_category(df::DDLm_Dictionary)

Find the category that is at the top of the category tree of `d`.
"""
find_head_category(df::DDLm_Dictionary) = begin
    explicit_head = df[:definition][df[:definition].class .== "Head",:master_id]
    if length(explicit_head) == 1
        return explicit_head[]
    elseif length(explicit_head) > 1
        @warn "Warning, more than one head category" explicit_head
    end
    find_head_category(df[:name])
end

"""
    find_top_level_cats(ref_dic::DDLm_Dictionary)

Find categories that should appear in the data block of a dictionary, as defined
by DDLm reference dictionary `ref_dic`.
"""
find_top_level_cats(ref_dic::DDLm_Dictionary) = begin
    domain = ref_dic[:dictionary_valid]
    acceptable = []
    for onerow in eachrow(domain)
        if onerow.application[1] == "Dictionary" && onerow.application[2] != "Prohibited"
            append!(acceptable,onerow.attributes)
        end
    end
    #println("All possibles: $acceptable")
    unique!(map(x->find_category(ref_dic,x),acceptable))
end

"""
    add_head_category!(df)

Add a missing head category to the DataFrame representation of a dictionary `df`
"""
add_head_category!(df,head_name) = begin
    hn = lowercase(head_name)
    new_info = Dict("_definition.id"=>hn,"_definition.scope"=>"Category",
                    "_definition.class"=>"Head")
    update_row!(df,new_info,"master_id",hn)
    new_info = Dict("_description.text"=>"This category is the parent of all other categories in the dictionary.")
    update_row!(df,new_info,"master_id",hn)
    new_info = Dict("_name.object_id"=>hn,"_name.category_id"=>hn)
    update_row!(df,new_info,"master_id",hn)
end


"""
All DDLm categories.
"""
const ddlm_categories = [
            "ALIAS",
            "CATEGORY",
            "CATEGORY_KEY",
            "DEFINITION",
            "DEFINITION_REPLACED",
            "DESCRIPTION",
            "DESCRIPTION_EXAMPLE",
            "DICTIONARY",
            "DICTIONARY_AUDIT",
            "DICTIONARY_VALID",
            "DICTIONARY_XREF",
            "ENUMERATION",
            "ENUMERATION_DEFAULT",
            "ENUMERATION_SET",
            "IMPORT",
            "IMPORT_DETAILS",
            "LOOP",
            "METHOD",
            "NAME",
            "TYPE",
            "UNITS"
]


"""
Turn a possibly relative URL into an absolute one. Will probably fail if file
component starts with "."
"""
fix_url(s::String,parent) = begin
    scheme = match(r"^[a-zA-Z]+:",s)
    if scheme == nothing
        if s[1]=='/'
            return URI(Path(s))
        elseif s[1]=="."  # really shouldn't accept this
            return URI(Path(joinpath(parent,s)))
        else
            return URI(Path(joinpath(parent,s)))
        end
    end
    return URI(s)
end

# Following code copied from URIs/uris.jl. For some reason
# this function was not recognised during precompilation

const absent = SubString("absent", 1, 0)

function URIs.URI(p::AbstractPath; query=absent, fragment=absent)
    if isempty(p.root)
        throw(ArgumentError("$p is not an absolute path"))
    end

    b = IOBuffer()
    print(b, "file://")

    if !isempty(p.drive)
        print(b, "/")
        print(b, p.drive)
    end

    for s in p.segments
        print(b, "/")
        print(b, URIs.escapeuri(s))
    end

    return URIs.URI(URIs.URI(String(take!(b))); query=query, fragment=fragment)
end

"""
    to_path(::URI)

Convert a file: URI to a Path.
Really belongs in FilePaths.jl but for now this will work.
"""
to_path(u::URI) = begin
    if Sys.iswindows()
        Path(unescapeuri(u.path[2:end]))
    else
        Path(unescapeuri(u.path))
    end
end

"""
    import_cache(d,original_dir)

Return an array with all import template files as DDLm dictionaries
ready for use. This routine is intended to save time re-reading
the imported files.
"""
import_cache(d,original_dir) = begin
    cached_dicts = Dict()
    if !haskey(d,:import) return cached_dicts end
    for one_row in eachrow(d[:import])
        import_table = one_row.get
        for one_entry in import_table
            import_def = missing
#           println("one import instruction: $one_entry")
    (location,block,mode,if_dupl,if_miss) = get_import_info(original_dir,one_entry)
            if mode == "Full"
                continue   # these are done separately
            end
            # Now carry out the import
            if !(location in keys(cached_dicts))
                #println("Now trying to import $location")
                try
                    cached_dicts[location] = DDLm_Dictionary(location,import_dir=original_dir)
                catch y
                    println("Error $y, backtrace $(backtrace())")
                    if if_miss == "Exit"
                        throw(error("Unable to find import for $location"))
                    end
                    continue
                end
            end

        end
    end
    return cached_dicts
end

"""
    resolve_imports!(d::Dict{Symbol,DataFrame},search_dir,cache, ignore)

Replace all `_import.get` statements with the contents of the imported dictionary.
`cache` contains a list of pre-imported files. `ignore` is the type of imports
to ignore.
"""
resolve_imports!(d::Dict{Symbol,DataFrame},search_dir,cache, ignore) = begin
    if !haskey(d,:import) return d end
    if ignore != :Contents
        resolve_templated_imports!(d,search_dir,cache)
        for i in eachrow(d[:import])
            filter!(e -> get(e, "mode", "Contents") != "Contents", i.get)
        end
        filter!(row -> !isempty(row.get), d[:import])
    end
    if ignore != :Full
        new_c = resolve_full_imports!(d,search_dir)
        for i in eachrow(d[:import])
            filter!(e -> get(e, "mode", "Contents") != "Full", i.get)
        end
        filter!(row -> !isempty(row.get), d[:import])
    end
    @debug "Imports now" d[:import]
    return d
end

get_import_info(original_dir,import_entry) = begin
    @debug "Now processing $import_entry"
    url = fix_url(import_entry["file"],original_dir)
    @debug "URI is $(url.scheme), $(url.path)"
    if url.scheme != "file"
        @debug "Looking in dir $original_dir, URI = $url"
        @error "Non-file URI cannot be handled: $(url.scheme) from $(import_entry["file"])"
    end
    location = to_path(url)
    block = import_entry["save"]
    mode = get(import_entry,"mode","Contents")
    if_dupl = get(import_entry,"dupl","Exit")
    if_miss = get(import_entry,"miss","Exit")
    return location,block,mode,if_dupl,if_miss
end

resolve_templated_imports!(d::Dict{Symbol,DataFrame},original_dir,cached_dicts) = begin
    for one_row in eachrow(d[:import])
        import_table = one_row.get
        for one_entry in import_table
            import_def = missing
#           println("one import instruction: $one_entry")
    (location,block,mode,if_dupl,if_miss) = get_import_info(original_dir,one_entry)
            if mode == "Full"
                continue   # these are done separately
            end
            # Now carry out the import
            if !(location in keys(cached_dicts))
                #println("Now trying to import $location")
                try
                    cached_dicts[location] = DDLm_Dictionary(location,import_dir=original_dir)
                catch y
                    println("Error $y, backtrace $(backtrace())")
                    if if_miss == "Exit"
                        throw(error("Unable to find import for $location"))
                    end
                    continue
                end
            end
            # now find the data block
            try
                import_def = cached_dicts[location][block]
            catch KeyError
                @error "Error $y, backtrace $(backtrace())"
                if if_miss == "Exit"
                    throw(error("When importing frame: Unable to find save frame $block in $location"))
                end
                continue
            end
            definition = one_row.master_id
            prior_contents = filter_on_name(d,definition)
            #println("Already present for $definition:")
            #println("$prior_contents")

#
# Merging each category. There are two cases where the category
# already exists in the importing block:
#
# (1) Single-row category ("Set").
# A single-row category may have only particular columns
# specified in the import frame, with the remainder expected
# to remain untouched.  We update the import information with
# the current information in the importing block. This occurs
# when both importing and importee have no more than one row
#
# (2) Multi-row category. ("Loop")
# If either importer or importee have more than one row in the
# category, the category is entirely replaced by the contents
# of the imported block.
#
# If the category does not exist at all, the imported block
# can simply be appended.
#
            for k in keys(import_def)
                if nrow(import_def[k])==0 continue end
                # drop old master id
                #println("Dropping :master_id from $k")
                #println("Processing $k for $definition")
                select!(import_def[k],Not(:master_id))
                if haskey(prior_contents,k) && nrow(prior_contents[k]) > 0
#                    println("$k already present for $definition")
#                    println("intersecting $(propertynames(prior_contents[k])) , $(propertynames(import_def[k]))")
                    dupls = intersect(propertynames(prior_contents[k]),propertynames(import_def[k]))
                    filter!(x->!(all(ismissing,prior_contents[k][!,x])) && !(all(ismissing,import_def[k][!,x])),dupls)
                    import_def[k][!,:master_id] .= definition
                    if length(dupls) > 0
#                       println("For $k handling duplicate defs $dupls")
                        if if_dupl == "Exit"
                            throw(error("Keys $dupls duplicated when importing from $block at $location in category '$k' for definition '$definition'"))
                        end
                        if if_dupl == "Ignore"
                            select!(import_def[k],Not(dupls))
                        elseif if_dupl == "Replace"
                            if nrow(import_def[k]>1)
                                d[k] = import_def[k]
                                continue
                            else
                                import_def[k][!,Not(dupls)] = prior_contents[k][!,Not(dupls)]
                            end
                        end
                    else
#                       println("imports were $(import_def[k])\n, updating with $(prior_contents[k])...")
                        for n in propertynames(prior_contents[k])
                            if !all(ismissing,prior_contents[k][!,n])
                                import_def[k][!,n] .= prior_contents[k][!,n]
                            end
                        end
#                       println("imports now $(import_def[k])")
                    end
                end
                import_def[k][!,:master_id] .= definition
                if haskey(d,k)
                    delete!(d[k],d[k][!,:master_id] .== definition)
                else
                    d[k] = DataFrame()
                end
                d[k] = vcat(d[k],import_def[k],cols=:union)
            end
        end   #of import list cycle
    end #of loop over blocks
    return d
end

# 
#A full import of Head into Head will add all definitions from the imported dictionary,
#and in addition will reparent all children of the imported Head category to the new
#Head category.  We first merge the two sets of save frames, and then fix the parent category
#of any definitions that had the old head category as parent. Note that the Cif
#object passed to us is just the save frames from a dictionary.
#
#The importing Head category is given a category of "." (nothing).
#

resolve_full_imports!(d::Dict{Symbol,DataFrame},original_dir) = begin
    for one_row in eachrow(d[:import])
        import_table = one_row.get
        for one_entry in import_table
    (location,block,mode,if_dupl,if_miss) = get_import_info(original_dir,one_entry)
            if mode == "Contents"
                continue
            end
            block_id = one_row.master_id
            if d[:definition][d[:definition].master_id .== block_id,:].class[] != "Head"
                @warn "Full mode imports into non-head categories not supported, ignored"
                continue
            end
            importee = DDLm_Dictionary(location,import_dir=original_dir)
            println("Full import of $location/$block/$if_dupl/$if_miss")
            importee_head = importee[block]
            if importee_head[:definition][!,:class][] != "Head"
                @warn "full mode imports of non-head categories not supported, ignored"
                continue
            end
            old_head = lowercase(importee_head[:name][!,:object_id][])
            new_head = d[:name][d[:name].master_id .== block_id,:].object_id[]
            # find duplicates
            all_defs = importee[:definition][!,:master_id]
            @debug "All imported defs:" all_defs
            prior_defs = d[:definition][!,:master_id]
            dups = filter(x-> count(isequal(x),all_defs)>0, prior_defs)
            if length(dups) > 0
                @debug "Duplicated frames" dups
                if if_dupl == "Replace"
                    throw(error("Option Replace for duplicated frame handling not yet implemented: $dups"))
                end
                if if_dupl == "Exit"
                    throw(error("Duplicate frames, Exit specified for this case. $dups"))
                end
                if if_dupl != "Ignore"
                    throw(error("Duplicate frames and option $if_dupl not recognised"))
                end
                # Remove definitions
                for (_,table) in importee.block
                    filter!(x-> !(x.master_id in dups), parent(table))
                end
            end
            # Remove old head category
            delete!(importee,block)
            # Remove old dictionary information
            oldname = importee[:dictionary].title[]
            delete!(importee.block,:dictionary)
            for k in keys(importee.block)
                filter!(x->x.master_id != oldname,parent(importee.block[k]))
            end
            # Concatenate them all
            for k in keys(importee.block)
                if !haskey(d,k)
                    d[k] = DataFrame()
                end
                d[k] = vcat(d[k],parent(importee.block[k]),cols=:union)
            end
            # And reparent
            transform!(d[:name],:category_id => ByRow(x -> if lowercase(x) == old_head new_head else x end) => :xxx)
            # And rename
            select!(d[:name],Not(:category_id))
            rename!(d[:name],:xxx => :category_id)
        end
    end
    return d
end

"""
    check_import_block(d::DDLm_Dictionary,name,attribute,val)

Check if the definition for `name` contains `attribute` equal
to `val` within an import block. `val` should be a single value.
"""
check_import_block(d::DDLm_Dictionary,name,cat,obj,val) = begin
    x = d[name]
    if !haskey(x,:import) || nrow(x[:import])!=1 return false end
    spec = x[:import].get[]
    for one_spec in spec
        if get(one_spec,"mode","Contents") == "Full" continue end
        templ_file_name = joinpath(Path(d.import_dir), one_spec["file"])
        if !(templ_file_name in keys(d.cached_imports))
            println("Warning: cannot find $templ_file_name when checking imports for $name")
            continue
        end
        templates = d.cached_imports[templ_file_name]
        target_block = templates[one_spec["save"]]
        # Find what we care about
        if haskey(target_block,cat)
            df = target_block[cat]
            if obj in propertynames(df)
                v = df[:,obj]
                return val in v
            end
        end
    end
    return false
end

check_import_block(d::DDLm_Dictionary,name,attribute,val) = begin
    cat,obj = split(attribute,".")
    cat = Symbol(cat[2:end])
    obj = Symbol(obj)
    check_import_block(d,name,cat,obj,val)
end
    
"""
Default values for DDLm attributes
"""
const ddlm_defaults = Dict(
(:definition,:class)=>"Datum",
(:definition,:scope)=>"Item",
(:dictionary,:class)=>"Instance",
(:dictionary_valid,:option)=>"Recommended",
(:enumeration,:mandatory)=>"Yes",
(:import_details,:if_dupl)=>"Exit",
(:import_details,:if_miss)=>"Exit",
    (:import_details,:mode)=>"Content",
    (:name,:linked_item_id)=>nothing,
    (:name,:category_id)=>nothing,
    (:name,:object_id)=>nothing,
(:method,:purpose)=>"Evaluation",
(:type,:container)=>"Single",
(:type,:contents)=>"Text",
(:type,:indices)=>"Text",
(:type,:purpose)=>"Describe",
(:type,:source)=>"Assigned",
(:units,:code)=>"Arbitrary"
)

"""
    enter_defaults(d)

Replace any missing values with the defaults for that value. The column type
is changed.
"""
enter_defaults(d) = begin
    for ((tab,obj),val) in ddlm_defaults
        if haskey(d,tab)
            if obj in propertynames(d[tab])
                d[tab][!,obj] = coalesce.(d[tab][!,obj],val)
            else
                insertcols!(d[tab],obj=>val)
            end
        end
    end
end

# **Reference dictionaries

# Reference dictionaries should include information about 'master_id', but
# this is absent from the surface of a DDLm dictionary. We add back in all of
# the master_id information

# Every category has a master_id data name, these are linked, and they form
# part of the key of every category. This information has to be added to the
# reference dictionary as if these were already present.

# `ref_dict` is a dictionary used for reference to obtain the list of global
# categories

"""
extra_reference!(t::Dict{Symbol,DataFrame})

Add identifier for definition data block to all relevant DDLm categories
"""
extra_reference!(t::Dict{Symbol,DataFrame}) = begin
    # add category key information
    cats = get_categories(t)
    head_cat = find_head_category(t)
    @debug "Head category is $head_cat"
    for one_cat in cats
        if one_cat == head_cat continue end #no head category
        target_name = "_$one_cat.master_id"
        push!(t[:category_key],Dict(:name => target_name,
                                    :master_id => one_cat),cols=:union)
        push!(t[:definition],Dict(:id => target_name,
                                  :class => "Attribute",
                                  :scope => "Item",
                                  :master_id => target_name),cols=:union)
        push!(t[:type],Dict(:contents => "Text",
                            :purpose => "Link",
                            :source => "Related",
                            :container => "Single",
                            :master_id => target_name),cols=:union)
        push!(t[:description],Dict(:text=> "Auto-generated dataname to satisfy relational model",
                                  :master_id => target_name),cols=:union)

        if Symbol(one_cat) in [:dictionary,:dictionary_audit,:dictionary_valid]
            push!(t[:name],Dict(:object_id => "master_id",
                                :category_id => one_cat,
                                :linked_item_id => "_dictionary.master_id",
                                :master_id => "_$one_cat.master_id"),cols=:union)
        else
            push!(t[:name],Dict(:object_id => "master_id",
                                :category_id => one_cat,
                                :linked_item_id => "_definition.master_id",
                                :master_id => target_name),cols=:union)
        end
    end
    unique!(t[:name])   #importing dictionaries may cause duplicate rows
    unique!(t[:category_key])
    unique!(t[:definition])
    unique!(t[:type])
    unique!(t[:description])
end

"""
Mapping of DDLm types to Julia types
"""
const type_mapping = Dict( "Text" => String,        
                           "Code" => Symbol("CaselessString"),                                                
                           "Name" => String,        
                           "Tag"  => String,         
                           "Uri"  => String,         
                           "Date" => String,  #change later        
                           "DateTime" => String,     
                           "Version" => String,     
                           "Dimension" => String,   
                           "Range"  => String, #TODO       
                           "Count"  => Integer,    
                           "Index"  => Integer,       
                           "Integer" => Integer,     
                           "Real" =>    Float64,        
                           "Imag" =>    Complex,  #really?        
                           "Complex" => Complex,     
                           "Symop" => String,       
                           # Implied     
                           # ByReference
                           "Array" => Array,
                           "Matrix" => Array,
                           "List" => Array{Any}
                           )

#TODO: Handle implied types

"""
    get_julia_type_name(cdic::DDLm_Dictionary,cat::AbstractString,obj::AbstractString)

Find the Julia type corresponding to `cat.obj` in `cdic`
"""
get_julia_type_name(cdic::DDLm_Dictionary,cat::AbstractString,obj::AbstractString) = begin
    if obj == "master_id" return AbstractString,"Single" end
    definition = cdic[find_name(cdic,cat,obj)]
    base_type = definition[:type][!,:contents][]
    cont_type = definition[:type][!,:container][]
    if cont_type == "Implied" cont_type = "Single" end  
    julia_base_type = get(type_mapping,base_type,String)
    return julia_base_type,cont_type
end

# return dimensions as an Array. Note that we do not handle
# asterisks, I think they are no longer allowed?
# The first dimension in Julia is number of rows, then number
# of columns. This is the opposite to dREL

"""
    get_dimensions(cdic::DDLm_Dictionary,cat,obj)

Get dimensions for `cat.obj` in Julia order (row,column,...)
"""
get_dimensions(cdic::DDLm_Dictionary,cat,obj) = begin
    definition = cdic[find_name(cdic,cat,obj)][:type]
    dims = :dimension in propertynames(definition) ? definition[!,:dimension][] : "[]"
    if ismissing(dims) dims = "[]" end
    final = eval(Meta.parse(dims))
    if length(final) > 1
        t = final[1]
        final[1] = final[2]
        final[2] = t
    end
    return final
end

"""
    get_container_type(cdic::DDLm_Dictionary,dataname)

Return the DDLm container type for `dataname` according to `cdic`.
"""
get_container_type(cdic::DDLm_Dictionary,dataname) = begin
    return cdic[dataname][:type][!,:container][]
end

"""
    get_implicit_list(d::DDLm_Dictionary)

Return a list of cat/columns that should not be included in the output
"""
get_implicit_list(d::DDLm_Dictionary) = begin
    return ()
end

# Capitalisation
#
# The style guide for dictionaries suggests that caseless values should
# have the first letter capitalised. We choose to match the case provided
# in the ddl dictionary.
"""
    conform_capitals!(d::DDLm_Dictionary,ref_dic)

Check and convert if necessary all values in `d` to match
the capitalisation of the values listed for that attribute in `ref_dic`, or
else have an initial capital letter if of type 'Code'.
"""
conform_capitals!(d::DDLm_Dictionary,ref_dic) = begin
    for (c,v) in d.block
        all_vals = parent(v)
        objs = propertynames(all_vals)
        for o in objs
            ref_def = ref_dic["_$c.$o"]
            @debug "Processing _$c.$o"
            if "contents" in names(ref_def[:type]) && ref_def[:type].contents[] != "Code" continue end
            if !haskey(ref_def,:enumeration_set) || size(ref_def[:enumeration_set],1) == 0

                # Single capital letter at front

                all_vals[!,o] .= map(all_vals[!,o]) do x
                    if !ismissing(x) && length(x) > 0
                        uppercase(x[1])*x[2:end]
                    else
                        x
                    end
                end
            else
                poss_vals = ref_def[:enumeration_set].state
                all_vals[!,o] .= map(all_vals[!,o]) do x
                    if !ismissing(x) && !(x in poss_vals)
                        myval = findfirst(y->lowercase(x)==lowercase(y), poss_vals)
                        if isnothing(myval)
                            @warn "Value $x not found for _$c.$o"
                            x
                        else
                            @debug "$x -> $(poss_vals[myval])"
                            poss_vals[myval]
                        end
                    else
                        x
                    end
                end
            end
        end
    end
end

"""
    make_cats_uppercase!(d::DDLm_Dictionary)

This will change all category-valued items in `d` to be fully uppercase.
"""
make_cats_uppercase!(d::DDLm_Dictionary) = begin
    
    # First definition.id
    
    transform!(parent(d.block[:definition]),:id => ByRow(x -> '.' in x ? x : uppercase(x)) => :id)
    
    # Now categories

    all_cats = get_categories(d)
    for one_cat in all_cats
        info = d[one_cat]
        @debug "Making $one_cat cat/obj uppercase"
        update_dict!(d,one_cat,"_name.category_id",uppercase(info[:name].category_id[]))
        update_dict!(d,one_cat,"_name.object_id",uppercase(info[:name].object_id[]))
    end
    
end
