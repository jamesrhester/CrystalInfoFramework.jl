# Next generation: reads the dictionary as a database the way
# the PDB intended
#
#==
The following semantics are important for DDLm dictionaries:
(1) Importation. A DDLm dictionary can import parts of definitions,
or complete dictionaries in order to describe the whole semantic space
(2) Parent-child. An object name may be referenced as if it were
part of the parent category; so if <c> is a child of <p>, and <q> is
an object in <c> (that is, "_c.q" is the dataname), then "p.q" refers
to the same item as "c.q" in dREL methods. It is not the case that
"_p.q" is a defined dataname.  The code here therefore implements only
the methods needed to find parents and children. 

Namespaces: data names in the dictionary may be assigned to a particular
namespace.

A reference dictionary may be supplied containing the definitions of the
DDLm attributes. A default reference dictionary is supplied.

==#
using Printf

export DDLm_Dictionary
export find_category,get_categories,get_set_categories
export translate_alias,list_aliases
export find_object,find_name
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
export get_default,lookup_default
export get_dic_name
export get_cat_class
export get_dic_namespace
export is_category
export find_head_category,add_head_category!
export get_julia_type_name,get_dimensions
import Base.show

const ddlm_std_ref = joinpath(@__DIR__,"ddl.dic")

struct DDLm_Dictionary <: abstract_cif_dictionary
    block::Dict{Symbol,GroupedDataFrame}
    func_defs::Dict{String,Function}
    func_text::Dict{String,Expr} #unevaluated Julia code
    def_meths::Dict{Tuple,Function}
    def_meths_text::Dict{Tuple,Expr}
    namespace::String
end

DDLm_Dictionary(c::NativeCif) = begin
    if length(keys(c))!= 1
        error("Error: Cif dictionary has more than one data block")
    end
    return DDLm_Dictionary(first(c).second)
end

DDLm_Dictionary(a::String;verbose=false) = DDLm_Dictionary(NativeCif(a,verbose=verbose))

DDLm_Dictionary(b::FullBlock) = begin
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
    # process imports - could we do this separately?
    resolve_imports!(all_dict_info,b.original_file)
    DDLm_Dictionary(all_dict_info,nspace)
end

"""
Construct a dictionary when provided with a collection of data frames indexed
by symbols. The symbols are DDLm attribute categories, and the dataframe columns
are the object_ids of the DDLm attributes of that category.
"""
DDLm_Dictionary(attr_dict::Dict{Symbol,DataFrame},nspace) = begin
    # Apply default values if not a template dictionary
    if attr_dict[:dictionary][!,:class][] != "Template"
        enter_defaults(attr_dict)
    end
    if attr_dict[:dictionary].class[] == "Reference"
        extra_reference!(attr_dict)
    end
    # group for efficiency
    gdf = Dict{Symbol,GroupedDataFrame}()
    for k in keys(attr_dict)
        gdf[k] = groupby(attr_dict[k],:master_id)
    end
    DDLm_Dictionary(gdf,Dict(),Dict(),Dict(),Dict(),nspace)
end

Base.keys(d::DDLm_Dictionary) = begin
    native = lowercase.(unique(first.(Iterators.flatten(values.(keys(v) for v in values(d.block))))))
    extra = []
    if haskey(d.block,:alias)
        extra = lowercase.(parent(d.block[:alias])[!,:definition_id])
    end
    return Iterators.flatten((native,extra))
end

Base.haskey(d::DDLm_Dictionary,k::String) = lowercase(k) in keys(d)

# Obtain all information about definition `k`
Base.getindex(d::DDLm_Dictionary,k) = begin
    canonical_name = find_name(d,k)
    return filter_on_name(d.block,canonical_name)
end

# If a symbol is passed we access the block directly.
Base.getindex(d::DDLm_Dictionary,k::Symbol) = parent(getindex(d.block,k)) #not a grouped data frame
Base.get(d::DDLm_Dictionary,k::Symbol,default) = parent(get(d.block,k,default))

"""
delete!(d::DDLm_Dictionary,k::String)

Remove all information associated with dataname `k`
"""
Base.delete!(d::DDLm_Dictionary,k::String) = begin
    canonical_name = find_name(d,k)
    for cat in keys(d.block)
        delete!(parent(d.block[cat]),parent(d.block[cat])[!,:master_id] .== canonical_name)
        # regroup
        d.block[cat] = groupby(parent(d.block[cat]),:master_id)
    end
end

# `k` is assumed to be already lower case
filter_on_name(d::Dict{Symbol,GroupedDataFrame},k) = begin
    info_dict = Dict{Symbol,DataFrame}()
    for cat in keys(d)
        try
            info_dict[cat] = d[cat][(master_id = k,)]
        catch KeyError
            info_dict[cat] = DataFrame()
        end
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
get_dic_namespace(d::DDLm_Dictionary) = begin
    if :namespace in propertynames(d[:dictionary])
        d[:dictionary][!,:namespace][]
    else
        "ddlm"
    end
end

list_aliases(d::DDLm_Dictionary,name;include_self=false) = begin
    result = d[name][:definition][:,:id]
    alias_block = get(d[name],:alias,nothing)
    if !isnothing(alias_block) && nrow(d[name][:alias]) > 0
        append!(result, alias_block[!,:definition_id])
    end
    if !include_self filter!(!isequal(name),result) end
    return result
end

translate_alias(d::DDLm_Dictionary,name) = begin
    lname = lowercase(name)
    # A template etc. dictionary has no defs
    if !haskey(d.block,:definition) return lname end
    if !(:id in propertynames(d[:definition])) return lname end
    if lname in lowercase.(d[:definition][!,:id]) return lname end
    if !haskey(d.block,:alias) return lname end
    potentials = d[:alias][lowercase.(d[:alias][!,:definition_id]) .== lname,:master_id]
    if length(potentials) == 1 return potentials[] end
    KeyError(name)
end

"""
Find the canonical name for `name`. If accessed in cat/obj format, search also child
categories. Note that the head category may not have a category associated with it.
"""
find_name(d::DDLm_Dictionary,name) = translate_alias(d,name)

find_name(d::DDLm_Dictionary,cat,obj) = begin
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

find_category(d::DDLm_Dictionary,dataname) = lowercase(d[dataname][:name][!,:category_id][])
find_object(d::DDLm_Dictionary,dataname) = lowercase(d[dataname][:name][!,:object_id][])
is_category(d::DDLm_Dictionary,name) = :scope in propertynames(d[name][:definition]) ? d[name][:definition][!,:scope][] == "Category" : false
get_categories(d) = lowercase.(d[:definition][d[:definition][!,:scope] .== "Category",:id])
get_cat_class(d::DDLm_Dictionary,catname) = :class in propertynames(d[catname][:definition]) ? d[catname][:definition][!,:class][] : "Datum"

is_set_category(d::DDLm_Dictionary,catname) = begin
    cat_decl = get_cat_class(d,catname)
    dic_type = d[:dictionary].class[]
    if dic_type != "Reference" && cat_decl == "Set" return true end
    if dic_type == "Reference" && catname == "dictionary" return true end
    return false
end

is_loop_category(d::DDLm_Dictionary,catname) = begin
    cat_decl = get_cat_class(d,catname)
    dic_type = d[:dictionary].class[]
    if dic_type == "Reference" && catname == "dictionary" return false end
    if dic_type == "Reference" && cat_decl == "Set" return true end
    return cat_decl == "Loop"
end

get_objs_in_cat(d::DDLm_Dictionary,cat) = begin
    temp = d[:name][!,:category_id]
    selector = map(x-> !isnothing(x) && lowercase(x) == lowercase(cat),temp)
    lowercase.(d[:name][selector,:object_id])
end


# Dictionary 'Set' categories are really loop categories with the definition id as the
# key data name

get_keys_for_cat(d::DDLm_Dictionary,cat;aliases=false) = begin
    loop_keys = lowercase.(d[:category_key][lowercase.(d[:category_key][!,:master_id]) .== lowercase(cat),:name])
    key_aliases = []
    if aliases
        for k in loop_keys
            append!(key_aliases,list_aliases(cat,k))
        end
    end
    append!(key_aliases,loop_keys)
    return key_aliases
end

get_linked_names_in_cat(d::DDLm_Dictionary,cat) = begin
    names = [n for n in get_names_in_cat(c,cat) if length(get(c[n][:name],:linked_item_id,[])) == 1]
    [n for n in names if get(c[n][:type],:purpose,["Datum"])[] != "SU"]
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

Return all categories that may only have one row. Note that a 'Set' category for a 
dictionary definition file can take multiple rows when separate definitions are
concatenated.
"""
get_set_categories(d::DDLm_Dictionary) = begin
    if d[:dictionary].class[] == "Instance"
        lowercase.(d[:definition][d[:definition][!,:class] .== "Set",:id])
    else
        ["dictionary"]
    end
end

get_loop_categories(d::DDLm_Dictionary) = begin
    if d[:dictionary].class[] == "Instance"
        lowercase.(d[:definition][d[:definition][!,:class] .== "Loop",:id])
    else
        lowercase.(d[:definition][d[:definition][!,:id] .!= "dictionary",:id])
    end
end

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

get_parent_category(d::DDLm_Dictionary,child) = begin
    lowercase(d[child][:name][!,:category_id][])
end

get_child_categories(d::DDLm_Dictionary,parent) = begin
    [c for c in get_categories(d) if get_parent_category(d,c) == lowercase(parent)]
end

get_single_keyname(d::DDLm_Dictionary,c) = begin
    keys = get_keys_for_cat(d,c)
    if length(keys) == 0
        error("Category $c has no keys defined")
    end
    if length(keys) == 1
        obj = keys[]
    else
        alternate = get(d[c][:category],:key_id,[])
        if length(alternate) == 0
            error("Category $c has no primitive key")
        end
        obj = alternate[]
    end
    d[obj][:name][!,:object_id][]
end

"""
Return a list (category,keyname) for all categories that have
a single key, where that key is not a child key of another
category. This latter case corresponds to a split single
category.
"""
get_single_key_cats(d::DDLm_Dictionary) = begin
    candidates = get_loop_categories(d)
    ck = (c for c in candidates if length(get_keys_for_cat(d,c))==1)
    keynames = ((r,d[r][:category_key][!,:name][]) for r in result)
    keynames = ( k for k in keynames if length(get(d[k[2]][:name],:linked_item_id,[])) == 0)
    return keynames
end

"""
Find the ultimately-linked dataname, if there is one. Protect against
simple self-referential loops.
"""
get_ultimate_link(d::DDLm_Dictionary,dataname::AbstractString) = begin
    if haskey(d,dataname)
        #println("Searching for ultimate value of $dataname")
        if :linked_item_id in names(d[dataname][:name]) &&
            d[dataname][:name][:linked_item_id][] != dataname
            return get_ultimate_link(d,d[dataname][:name][:linked_item_id][])
        end
    end
    return dataname
end

get_default(b::DDLm_Dictionary,s) = begin
    info = get(b[s],:enumeration,missing)
    if !ismissing(info)
        info = get(info,:default,[missing])[]
    end
    return info
end

#==   Lookup 

A default value may be tabulated, and some other value in the
current packet is used to index into the table. `cp` is an
object with symbolic properties corresponding to the
items in a category.

==#

lookup_default(dict::DDLm_Dictionary,dataname::String,cp) = begin
    definition = dict[dataname][:enumeration]
    index_name = :def_index_id in propertynames(definition) ? definition[!,:def_index_id][] : missing
    if ismissing(index_name) return missing end
    object_name = find_object(dict,index_name)
    # Note non-deriving form of getproperty
    println("Looking for $object_name in $(getfield(getfield(cp,:source_cat),:name))")
    current_val = getproperty(cp,Symbol(object_name))
    print("Indexing $dataname using $current_val to get")
    # Now index into the information. ddl.dic states that this is of type 'Code'
    # so we apply the CaselessString constructor
    indexlist = CaselessString.(dict[dataname][:enumeration_default][!,:index])
    pos = indexin([current_val],indexlist)
    if pos[1] == nothing return missing end
    return dict[dataname][:enumeration_default][!,:value][pos[1]]
end

# Methods for setting and retrieving evaluated functions
#== Extract the dREL text from the dictionary, if any
==#
load_func_text(dict::DDLm_Dictionary,dataname::String,meth_type::String) =  begin
    full_def = dict[dataname]
    func_text = full_def[:method]
    if size(func_text,2) == 0   #nothing
        return ""
    end
    # TODO: allow multiple methods
    eval_meths = func_text[func_text[!,:purpose] .== meth_type,:]
    println("Meth size for $dataname is $(size(eval_meths))")
    if size(eval_meths,1) == 0
        return ""
    end
    eval_meth = eval_meths[!,:expression][]
end

"""
Remove all methods from the dictionary. This will stop any
automatic derivation taking place.
"""
remove_methods!(dict::DDLm_Dictionary) = begin
    dict.block[:method] = groupby(DataFrame([[]],[:master_id]),:master_id)
end
"""
as_data(d::DDLm_Dictionary)

Return an object `o` accessible using 
`o[attribute]` where `attribute`
is a ddlm attribute.
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

set_func!(d::DDLm_Dictionary,func_name::String,func_text::Expr,func_code) = begin
    d.func_defs[func_name] = func_code
    d.func_text[func_name] = func_text
    println("All funcs: $(keys(d.func_defs))")
end

get_func(d::DDLm_Dictionary,func_name::String) = d.func_defs[func_name]
get_func_text(d::DDLm_Dictionary,func_name::String) = d.func_text[func_name]
has_func(d::DDLm_Dictionary,func_name::String) = begin
    try
        d.func_defs[func_name]
    catch KeyError
        return false
    end
    return true
end

# Methods for setting and retrieving definition functions
has_default_methods(d::DDLm_Dictionary) = true
has_def_meth(d::DDLm_Dictionary,func_name::String,ddlm_attr::String) = haskey(d.def_meths,(func_name,ddlm_attr))
get_def_meth(d::DDLm_Dictionary,func_name::String,ddlm_attr::String) = d.def_meths[(func_name,ddlm_attr)]
get_def_meth_txt(d::DDLm_Dictionary,func_name::String,ddlm_attr::String) = d.def_meths_text[(func_name,ddlm_attr)]

set_func!(d::DDLm_Dictionary,func_name::String,ddlm_attr::String,func_text::Expr,func_code) = begin
    d.def_meths[(func_name,ddlm_attr)] = func_code
    d.def_meths_text[(func_name,ddlm_attr)] = func_text
end

get_parent_name(d::DDLm_Dictionary,name) = begin
    d[name][:name][!,:category_id][]
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
find_head_category(ds)

Find the category that is at the top of the category tree.
`df` is essentially the `:name` category as a DataFrame. If
`definition.class == Head` returns a unique value that is
preferred.
"""
find_head_category(df::DataFrame) = begin
    # get first and follow it up
    some_cat = lowercase(df.category_id[1])
    old_cat = some_cat
    while true
        some_cat = lowercase.(df[lowercase.(df[!,:object_id]) .== some_cat,:category_id])
        if length(some_cat) == 0 || some_cat[] == old_cat break end
        println("$old_cat -> $some_cat")
        old_cat = some_cat[]
    end
    println("head category is $old_cat")
    return old_cat
end

find_head_category(df::Dict) = begin
    if haskey(df,:definition)
        explicit_head = df[:definition][df[:definition].class .== "Head",:master_id]
        if length(explicit_head) == 1
            return explicit_head[]
        elseif length(explicit_head) > 1
            println("Warning, more than one head category: $explicit_head")
        end
    end
    find_head_category(df[:name])
end

find_head_category(df::DDLm_Dictionary) = begin
    explicit_head = df[:definition][df[:definition].class .== "Head",:master_id]
    if length(explicit_head) == 1
        return explicit_head[]
    elseif length(explicit_head) > 1
        println("Warning, more than one head category: $explicit_head")
    end
    find_head_category(df[:name])
end

"""
Find categories that are at the top level of the dictionary. `ref_dic` is a DDLm
attribute dictionary. 
"""
find_top_level_cats(ref_dic::DDLm_Dictionary) = begin
    domain = ref_dic[:dictionary_valid]
    acceptable = []
    for onerow in eachrow(domain)
        if onerow.application[1] == "Dictionary" && onerow.application[2] != "Prohibited"
            append!(acceptable,onerow.attributes)
        end
    end
    println("All possibles: $acceptable")
    unique!(map(x->find_category(ref_dic,x),acceptable))
end

"""
add_head_category!(df)

Add a missing head category to the DataFrame dictionary `df`
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

#== Resolve imports
This routine will substitute all _import.get statements with the imported dictionary. Generally
the only reason that you would not do this is if you are editing the dictionary rather than
using it.
==#

#== Turn a possibly relative URL into an absolute one. Will probably fail with pathological
URLs containing colons early on ==#

fix_url(s::String,parent::String) = begin
    if s[1]=='/'
        return "file://"*s
    elseif s[1]=="."
        return "file://"*parent*s[2:end]
    else
        return "file://"*parent*"/"*s
    end
    return s
end

resolve_imports!(d::Dict{Symbol,DataFrame},original_file) = begin
    if !haskey(d,:import) return d end
    resolve_templated_imports!(d,original_file)
    new_c = resolve_full_imports!(d,original_file)
    # do we need to remove import commands?
    return d
end

get_import_info(original_dir,import_entry) = begin
    #println("Now processing $import_entry")
    fixed = fix_url(import_entry["file"],original_dir)
    url = URI(fixed)
    #println("URI is $(url.scheme), $(url.path)")
    if url.scheme != "file"
        error("Non-file URI cannot be handled: $(url.scheme) from $(import_entry["file"])")
    end
    location = url.path
    block = import_entry["save"]
    mode = get(import_entry,"mode","Contents")
    if_dupl = get(import_entry,"if_dupl","Exit")
    if_miss = get(import_entry,"if_miss","Exit")
    return location,block,mode,if_dupl,if_miss
end

resolve_templated_imports!(d::Dict{Symbol,DataFrame},original_file) = begin
    cached_dicts = Dict() # so as not to read twice
    original_dir = dirname(original_file)
    for one_row in eachrow(d[:import])
        import_table = one_row.get
        for one_entry in import_table
            import_def = missing
            println("one import instruction: $one_entry")
    (location,block,mode,if_dupl,if_miss) = get_import_info(original_dir,one_entry)
            if mode == "Full"
                continue   # these are done separately
            end
            # Now carry out the import
            if !(location in keys(cached_dicts))
                #println("Now trying to import $location")
                try
                    cached_dicts[location] = DDLm_Dictionary(location)
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
                println("Error $y, backtrace $(backtrace())")
                if if_miss == "Exit"
                    throw(error("When importing frame: Unable to find save frame $block in $location"))
                end
                continue
            end
            definition = one_row.master_id
            prior_contents = filter_on_name(d,definition)
            #println("Already present for $definition:")
            #println("$prior_contents")

#==
Merging each category. There are two cases where the category
already exists in the importing block:

(1) Single-row category ("Set").
A single-row category may have only particular columns
specified in the import frame, with the remainder expected
to remain untouched.  We update the import information with
the current information in the importing block. This occurs
when both importing and importee have no more than one row

(2) Multi-row category. ("Loop")
If either importer or importee have more than one row in the
category, the category is entirely replaced by the contents
of the imported block.

If the category does not exist at all, the imported block
can simply be appended.
==#
            for k in keys(import_def)
                if nrow(import_def[k])==0 continue end
                # drop old master id
                #println("Dropping :master_id from $k")
                #println("Processing $k for $definition")
                select!(import_def[k],Not(:master_id))
                if haskey(prior_contents,k) && nrow(prior_contents[k]) > 0
                    println("$k already present for $definition")
                    println("intersecting $(propertynames(prior_contents[k])) , $(propertynames(import_def[k]))")
                    dupls = intersect(propertynames(prior_contents[k]),propertynames(import_def[k]))
                    filter!(x->!(all(ismissing,prior_contents[k][!,x])) && !(all(ismissing,import_def[k][!,x])),dupls)
                    import_def[k][!,:master_id] .= definition
                    if length(dupls) > 0
                        println("For $k handling duplicate defs $dupls")
                        if if_dupl == "Exit"
                            throw(error("Keys $dupls duplicated when importing from $block at $location in category $k"))
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
                        println("imports were $(import_def[k])\n, updating with $(prior_contents[k])...")
                        for n in propertynames(prior_contents[k])
                            if !all(ismissing,prior_contents[k][!,n])
                                import_def[k][!,n] .= prior_contents[k][!,n]
                            end
                        end
                        println("imports now $(import_def[k])")
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

#== 
A full import of Head into Head will add all definitions from the imported dictionary,
and in addition will reparent all children of the imported Head category to the new
Head category.  We first merge the two sets of save frames, and then fix the parent category
of any definitions that had the old head category as parent. Note that the NativeCif
object passed to us is just the save frames from a dictionary.

The importing Head category is given a category of "." (nothing).
==#

resolve_full_imports!(d::Dict{Symbol,DataFrame},original_file) = begin
    original_dir = dirname(original_file)
    for one_row in eachrow(d[:import])
        import_table = one_row.get
        for one_entry in import_table
    (location,block,mode,if_dupl,if_miss) = get_import_info(original_dir,one_entry)
            if mode == "Contents"
                continue
            end
            block_id = one_row.master_id
            if d[:definition][d[:definition].master_id .== block_id,:].class[] != "Head"
                println("Warning:  full mode imports into non-head categories not supported, ignored")
                continue
            end
            importee = DDLm_Dictionary(location)
            importee_head = importee[block]
            if importee_head[:definition][!,:class][] != "Head"
                println("WARNING: full mode imports of non-head categories not supported, ignored")
                continue
            end
            old_head = lowercase(importee_head[:name][!,:object_id][])
            new_head = d[:name][d[:name].master_id .== block_id,:].object_id[]
            # find duplicates
            all_defs = importee[:definition][!,:master_id]
            #println("All visible defs: $all_defs")
            dups = filter(x-> count(isequal(x),all_defs)>1,all_defs)
            if length(dups) > 0
                println("Duplicated frames: $dups")
                throw(error("Duplicated frame handling not yet implemented: $dups"))
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
            transform!(d[:name],:category_id => (x -> if x == old_head new_head else x end) => :xxx)
            # And rename
            select!(d[:name],Not(:category_id))
            rename!(d[:name],:xxx => :category_id)
        end
    end
    return d
end

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
        if haskey(d,tab) && obj in propertynames(d[tab])
            d[tab][!,obj] = coalesce.(d[tab][!,obj],val)
        end
    end
end

# == Reference dictionaries

# Reference dictionaries should include information about 'master_id', but
# this is absent from the surface of a DDLm dictionary. We add back in all of
# the master_id information

# Every category has a master_id data name, these are linked, and they form
# part of the key of every category. This information has to be added to the
# reference dictionary as if these were already present.

# `ref_dict` is a dictionary used for reference to obtain the list of global
# categories
#
extra_reference!(t::Dict{Symbol,DataFrame}) = begin
    # add category key information
    cats = get_categories(t)
    head_cat = find_head_category(t)
    println("Head category is $head_cat")
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


# Output

show(io::IO,::MIME"text/cif",ddlm_dic::DDLm_Dictionary) = begin
    dicname = ddlm_dic[:dictionary].title[]
    write(io,"#\\#CIF_2.0\n")
    write(io,"""
##############################################################
#
#        $dicname (DDLm)
#
##############################################################\n""")
    write(io,"data_$dicname\n")
    top_level = ddlm_dic[:dictionary]
    show_set(io,"dictionary",top_level)
    # And the unlooped top-level stuff
    top_level = ddlm_dic[dicname]
    for c in keys(top_level)
        if c == :dictionary continue end
        if nrow(top_level[c]) == 1
            show_set(io,String(c),top_level[c])
        end
    end
    # Now for the rest
    head = find_head_category(ddlm_dic)
    show_one_def(io,head,ddlm_dic[head])
    all_cats = sort!(get_categories(ddlm_dic))
    for one_cat in all_cats
        if one_cat == head continue end
        cat_info = ddlm_dic[one_cat]
        show_one_def(io,one_cat,cat_info)
        items = get_names_in_cat(ddlm_dic,one_cat)
        for one_item in items
            show_one_def(io,one_item,ddlm_dic[one_item])
        end
    end
    # And the looped top-level stuff
    top_level = ddlm_dic[dicname]
    for c in keys(top_level)
        if c == :dictionary continue end
        if nrow(top_level[c]) > 1
            show_loop(io,String(c),top_level[c])
        end
    end
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

get_container_type(cdic::DDLm_Dictionary,dataname) = begin
    return cdic[dataname][:type][!,:container][]
end

