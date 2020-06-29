# Enough support for DDL2 dictionaries to allow them to be used
# for category construction

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

"""

This DDL2 dictionary type does not handle multiple items defined
in a single block
"""
DDL2_Dictionary(base_b::FullBlock) = begin
    # create the definition names
    defs = get_frames(b)
    bnames = collect(keys(defs))
    match_dict = Dict()
    # create lookup tables for cat,obj if not a template dictionary
    cat_obj_dict = Dict()
    parent_dict = Dict()
    for k in bnames
        if haskey(defs[k],"_category.id")
            match_dict[defs[k]["_category.id"]][] = k
        elseif haskey(defs[k],"_item.name")
            match_dict[defs[k]["_item.name"]][] = k
        else
            throw(error("Def with no name: $k"))
        end
    end

    # create all aliases
    extra_aliases = generate_aliases(defs,alias_att = "_item_aliases.alias_name")
    merge!(match_dict,extra_aliases)

    # now the information for cat/obj lookup
    for k in bnames
        if haskey(defs[k],"_item.category_id")
            obj_id = lowercase(split(defs[k]["_item.name"][],".")[end])
            cat_obj_dict[(defs[k]["_item.category_id"],obj_id)] = k
        end
    end
    return DDL2_Dictionary(b,match_dict,cat_obj_dict,Dict())
end

# Methods needed for creating DDLm Loop categories

Base.keys(d::DDL2_Dictionary) = keys(d.definitions)
Base.haskey(d::DDL2_Dictionary,k::String) = haskey(d.definitions,k)
Base.getindex(d::DDL2_Dictionary,k::String) = begin
    get_save_frame(d.block,d.definitions[lowercase(k)])
end

find_category(d::DDL2_Dictionary,dataname) = begin
    block = d[dataname]
    lowercase(get(block,"_item.category_id",[""])[])
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

list_aliases(d::DDL2_Dictionary,name;include_self=false) = begin
    starter = []
    if include_self push!(starter,d[name]["_item.name"][]) end
    return append!(starter, get(d[name],"_item_aliases.alias_name",[]))
end
