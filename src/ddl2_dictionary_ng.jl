# Enough support for DDL2 dictionaries to allow them to be used
# for category construction
#
# Next generation: reads the dictionary as a database the way
# the PDB intended, and split on '.' for cat/obj
#
export DDL2_Dictionary

struct DDL2_Dictionary <: abstract_cif_dictionary
    block::Dict{Symbol,DataFrame}
    parent_lookup::Dict{String,String}
end

DDL2_Dictionary(c::NativeCif) = begin
    if length(keys(c))!= 1
        error("Error: Cif dictionary has more than one data block")
    end
    return DDL2_Dictionary(first(c).second,lowercase(first(keys(c))))
end

DDL2_Dictionary(a::String;verbose=false) = DDL2_Dictionary(NativeCif(a,verbose=verbose))

DDL2_Dictionary(b::FullBlock,blockname::AbstractString) = begin
    all_dict_info = Dict{Symbol,DataFrame}()
    # loop over all blocks, storing information
    defs = get_frames(b)
    bnames = keys(defs)
    for k in bnames
        # process loops
        loops = get_loop_names(defs[k])
        for one_loop in loops
            new_info = get_loop(defs[k],first(one_loop))
            update_dict!(all_dict_info,new_info,lowercase(k))
        end
        # process unlooped
        unlooped = [x for x in keys(defs[k]) if !(x in Iterators.flatten(loops))]
        cats = unique([split(x,'.')[1][2:end] for x in unlooped])
        println("Cats for $k: $cats")
        for one_cat in cats
            dnames = filter(x-> split(x,'.')[1][2:end] == one_cat,unlooped)
            new_vals = (defs[k][x][] for x in dnames)
            @assert length(new_vals)>0
            update_row!(all_dict_info,Dict(zip(dnames,new_vals)),lowercase(k))
        end
    end
    # and now store information in the enclosing block
    loops = get_loop_names(b)
    for one_loop in loops
        new_info = get_loop(b,first(one_loop))
        update_dict!(all_dict_info,new_info,blockname)
    end
    # process unlooped
    unlooped = [x for x in keys(b) if !(x in Iterators.flatten(loops))]
    cats = unique([split(x,'.')[1][2:end] for x in unlooped])
    for one_cat in cats
        dnames = filter(x-> split(x,'.')[1][2:end] == one_cat,unlooped)
        new_vals = (b[x][] for x in dnames)
        update_row!(all_dict_info,Dict(zip(dnames,new_vals)),blockname)
    end
    # Add implicit values
    populate_implicits(all_dict_info)
    # now the parent lookup: DDL2 dictionaries store children...
    parent_dict = generate_parents(defs)
    return DDL2_Dictionary(all_dict_info,parent_dict)
end

# Methods needed for creating DDLm Loop categories

Base.keys(d::DDL2_Dictionary) = Iterators.flatten((d.block[:item][!,:name],d.block[:category][!,:id]))
Base.haskey(d::DDL2_Dictionary,k::String) = k in keys(d)

# Obtain all information about item `k` or category `k`
Base.getindex(d::DDL2_Dictionary,k::String) = begin
    info_dict = Dict{Symbol,DataFrame}()
    if '.' in k search_space = children_of_item else search_space = children_of_category end
    for one_child in search_space
        cat = Symbol(find_category(d,one_child))
        if !haskey(d.block,cat) continue end
        obj = Symbol(find_object(d,one_child))
        println("Filtering on $cat / $obj")
        info_dict[cat] = d.block[cat][d.block[cat][!,obj] .== k,:]
        if nrow(info_dict[cat]) == 0 delete!(info_dict,cat) end
    end
    return info_dict
end

get_dic_name(d::DDL2_Dictionary) = d.block[:dictionary][:title][]
get_dic_namespace(d::DDL2_Dictionary) = "ddl2"  #single namespace

find_category(d::DDL2_Dictionary,dataname) = begin
    return split(dataname,'.')[1][2:end]
end

find_object(d::DDL2_Dictionary,dataname) = begin
    if occursin(".",dataname)
        return split(dataname,".")[end]
    end
    return nothing
end

get_keys_for_cat(d::DDL2_Dictionary,catname) = begin
    d[catname][:category_key][!,:name]
end

# Remember that a DDL2 save frame uses its name
list_aliases(d::DDL2_Dictionary,name;include_self=false) = begin
    d.block[name][:item_aliases][!,:alias_name]
end

# No aliases supported for this one
translate_alias(d::DDL2_Dictionary,name) = begin
    return name
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

"""
Update the appropriate table of `all_dict_info` with
the contents of `new_info`, filling in implicit values
with `blockname`
"""
update_dict!(all_dict_info,new_info,blockname) = begin
    tablename = Symbol(split(String(first(names(new_info))),'.')[1][2:end])
    rename!(x-> Symbol(split(String(x),'.')[end]),new_info)
    if !haskey(all_dict_info,tablename)
        all_dict_info[tablename] = DataFrame()
    end
    new_info[!,:__blockname] = fill(blockname,nrow(new_info))
    all_dict_info[tablename] = vcat(all_dict_info[tablename],new_info,cols=:union)
end

update_row!(all_dict_info,new_vals,blockname) = begin
    catname = Symbol(split(first(keys(new_vals)),'.')[1][2:end])
    if !haskey(all_dict_info,catname)
        all_dict_info[catname] = DataFrame()
    end
    final_vals = Dict((Symbol(split(x.first,'.')[end]),x.second) for x in new_vals)
    final_vals[:__blockname] = blockname
    #push!(all_dict_info[catname],final_vals,cols=:union) dataframes 0.21
    all_dict_info[catname] = vcat(all_dict_info[catname],DataFrame(final_vals),cols=:union)
end

# DDL2 uses implicit values based on the block name
const implicits = [
          "_item.name",                
          "_item_aliases.name",             
          "_item_default.name",            
          "_item_dependent.name",           
          "_item_description.name",         
          "_item_enumeration.name",         
          "_item_examples.name",         
          "_item_linked.parent_name",       
          "_item_methods.name",       
          "_item_range.name",      
          "_item_related.name",     
          "_item_type.name",    
          "_item_type_conditions.name",   
          "_item_structure.name",  
          "_item_sub_category.name",        
          "_item_units.name",
          "_category_examples.id",        
          "_category_key.id",       
          "_category_group.category_id",   
          "_category_methods.category_id", 
    "_item.category_id",
    "_datablock.id",             
    "_datablock_methods.datablock_id",  
    "_dictionary.datablock_id",
    # category.implicit_key   -- should be datablock.id
]             

const children_of_item =        [   "_item.name",                
          "_item_aliases.name",             
          "_item_default.name",            
          "_item_dependent.name",           
          "_item_description.name",         
          "_item_enumeration.name",         
          "_item_examples.name",         
          "_item_linked.parent_name",       
          "_item_methods.name",       
          "_item_range.name",      
          "_item_related.name",     
          "_item_type.name",    
          "_item_type_conditions.name",   
          "_item_structure.name",  
          "_item_sub_category.name",        
          "_item_units.name" ]

const children_of_category = [ "_category.id",
    "_category_examples.id",        
    "_category_key.id",       
    "_category_group.category_id",   
    "_category_methods.category_id"
]

populate_implicits(all_tables) = begin
    cats = map(x->Symbol(split(x,'.')[1][2:end]),implicits)
    objs = map(x->Symbol(split(x,'.')[2]),implicits)
    for (cat,table) in all_tables
        if cat in cats
            target_name = objs[indexin([cat],cats)[]]
            if !(target_name in names(table))
                rename!(table,(:__blockname=>target_name))
                println("Added implicit value for $cat.$target_name")
            end
        end
    end
end

