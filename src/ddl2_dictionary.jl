# Enough support for DDL2 dictionaries to allow them to be used
# for category construction
export DDL2_Dictionary

struct DDL2_Dictionary <: abstract_cif_dictionary
    block::FullBlock
    definitions::Dict{String,String}
    by_cat_obj::Dict{Tuple,String}
    parent_lookup::Dict{String,String}
end

DDL2_Dictionary(c::NativeCif) = begin
    if length(keys(c))!= 1
        error("Error: Cif dictionary has more than one data block")
    end
    return DDL2_Dictionary(first(c).second)
end

DDL2_Dictionary(a::String;verbose=false) = DDL2_Dictionary(NativeCif(a,verbose=verbose))

"""

This DDL2 dictionary type does not handle multiple items defined
in a single block
"""
DDL2_Dictionary(b::FullBlock) = begin
    # create the definition names
    defs = get_frames(b)
    bnames = keys(defs)
    match_dict = Dict()
    # create lookup tables for cat,obj if not a template dictionary
    cat_obj_dict = Dict()
    parent_dict = Dict()
    for k in bnames
        if haskey(defs[k],"_category.id")
            match_dict[defs[k]["_category.id"][]] = k
        elseif haskey(defs[k],"_item.name")
            for one_name in defs[k]["_item.name"]
                if haskey(match_dict,one_name)
                    println("WARNING:overwriting block name for $one_name, was $(match_dict[one_name]), now $k")
                end
                match_dict[one_name] = k
            end
        else
            println("FYI, def with no name: $k")
        end
    end

    # create all aliases
    extra_aliases = generate_aliases(defs,alias_att = "_item_aliases.alias_name")
    merge!(match_dict,extra_aliases)

    # now the information for cat/obj lookup
    # remembering the possibility of multiple defs in one
    for k in bnames
        if haskey(defs[k],"_item.category_id")
            for (cat,name) in zip(defs[k]["_item.category_id"],defs[k]["_item.name"])
                obj_id = lowercase(split(name,".")[end])
                cat_obj_dict[(cat,obj_id)] = k
            end
        end
    end

    # now the parent lookup: DDL2 dictionaries store children...
    parent_dict = generate_parents(defs)
    return DDL2_Dictionary(b,match_dict,cat_obj_dict,parent_dict)
end

# Methods needed for creating DDLm Loop categories

Base.keys(d::DDL2_Dictionary) = keys(d.definitions)
Base.haskey(d::DDL2_Dictionary,k::String) = haskey(d.definitions,k)
Base.getindex(d::DDL2_Dictionary,k::String) = begin
    get_save_frame(d.block,d.definitions[lowercase(k)])
end

get_dic_name(d::DDL2_Dictionary) = d.block["_dictionary.title"][]
get_dic_namespace(d::DDL2_Dictionary) = "ddl2"  #single namespace

find_category(d::DDL2_Dictionary,dataname) = begin
    block = d[dataname]
    println("Seeking category for $dataname")
    pos = indexin([dataname],get(block,"_item.name",[]))[]
    all_cats = get(block,"_item.category_id",[""])
    if length(all_cats) >= pos all_cats[pos] else "" end
end

find_object(d::DDL2_Dictionary,dataname) = begin
    if occursin(".",dataname)
        return split(dataname,".")[end]
    end
    return nothing
end

get_keys_for_cat(d::DDL2_Dictionary,catname) = begin
    loop_keys = d[catname]["_category_key.name"]
end

# Remember that a DDL2 save frame uses its name
list_aliases(d::DDL2_Dictionary,name;include_self=false) = begin
    starter = []
    if include_self push!(starter,name) end
    return append!(starter, get(d[name],"_item_aliases.alias_name",[]))
end

translate_alias(d::DDL2_Dictionary,name) = begin
    options = get(d[name],"_item.name",[name])
    if length(options) == 1 return options[] end
    # use the blockname
    return d.definitions[name]
end

"""
Find the canonical name for `name`. For DDL2 this is not implemented,
that is, aliases are not recognised.
"""
find_name(d::DDL2_Dictionary,name) = begin
    return name
end

find_name(d::DDL2_Dictionary,cat,obj) = begin
    return "_"*cat*"."*obj
end

"""

Create a dictionary allowing lookup in the direction child -> parent
"""
generate_parents(defs) = begin
    child_list = []
    parent_list = []
    for d in keys(defs)
        if haskey(defs[d],"_item_linked.child_name")
            append!(child_list,defs[d]["_item_linked.child_name"])
            append!(parent_list,defs[d]["_item_linked.parent_name"])
        end
    end
    return Dict(collect(zip(child_list,parent_list)))
end

get_parent_name(d::DDL2_Dictionary,name) = begin
    return get(d.parent_lookup,name,nothing)
end

get_cat_class(d::DDL2_Dictionary,name) = "Loop"
