# Enough support for DDL2 dictionaries to allow them to be used
# for category construction
#
# Next generation: reads the dictionary as a database the way
# the PDB intended, and split on '.' for cat/obj
#
export DDL2_Dictionary,as_data

struct DDL2_Dictionary <: abstract_cif_dictionary
    block::Dict{Symbol,DataFrame}
    func_defs::Dict{String,Function}
    func_text::Dict{String,Expr} #unevaluated Julia code
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
            update_dict!(all_dict_info,new_info,CaselessString(k))
        end
        # process unlooped
        unlooped = [x for x in keys(defs[k]) if !(x in Iterators.flatten(loops))]
        cats = unique([split(x,'.')[1][2:end] for x in unlooped])
        #println("Cats for $k: $cats")
        for one_cat in cats
            dnames = filter(x-> split(x,'.')[1][2:end] == one_cat,unlooped)
            new_vals = (defs[k][x][] for x in dnames)
            @assert length(new_vals)>0
            update_row!(all_dict_info,Dict(zip(dnames,new_vals)),CaselessString(k))
        end
    end
    # and now store information in the enclosing block
    loops = get_loop_names(b)
    for one_loop in loops
        new_info = get_loop(b,first(one_loop))
        update_dict!(all_dict_info,new_info,CaselessString(blockname))
    end
    # process unlooped
    unlooped = [x for x in keys(b) if !(x in Iterators.flatten(loops))]
    cats = unique([split(x,'.')[1][2:end] for x in unlooped])
    for one_cat in cats
        dnames = filter(x-> split(x,'.')[1][2:end] == one_cat,unlooped)
        new_vals = (b[x][] for x in dnames)
        update_row!(all_dict_info,Dict(zip(dnames,new_vals)),CaselessString(blockname))
    end
    # Add implicit values
    populate_implicits(all_dict_info)
    # now the parent lookup: DDL2 dictionaries store children...
    parent_dict = generate_parents(defs)
    # And add category, object
    add_cat_obj!(all_dict_info)
    # Remove any duplicates
    for (x,df) in all_dict_info
        unique!(df,Not(r"^__blockname"))
    end
    return DDL2_Dictionary(all_dict_info,Dict(),Dict(),parent_dict)
end

"""
Construct a dictionary when provided with a collection of data frames indexed
by symbols. The symbols are DDL2 attribute categories, and the dataframe columns
are the object_ids of the DDL2 attributes of that category.

TODO: work out child-parent relations as well
"""
DDL2_Dictionary(attr_dict::Dict{Symbol,DataFrame},nspace) = begin
    # make sure all rows are unique
    for (_,df) in attr_dict
        unique!(df,Not(r"^__blockname"))
    end
    DDL2_Dictionary(attr_dict,Dict(),Dict(),Dict())
end

# Methods needed for creating DDLm Loop categories

Base.keys(d::DDL2_Dictionary) = Iterators.flatten((d.block[:item][!,:name],d.block[:category][!,:id]))
Base.haskey(d::DDL2_Dictionary,k::String) = k in keys(d)

# Obtain all information about item `k` or category `k`
Base.getindex(d::DDL2_Dictionary,k) = begin
    lk = lowercase(k)
    info_dict = Dict{Symbol,DataFrame}()
    if '.' in k search_space = children_of_item else search_space = children_of_category end
    for one_child in search_space
        cat = Symbol(find_category(d,one_child))
        if !haskey(d.block,cat) continue end
        obj = Symbol(find_object(d,one_child))
        #println("Filtering on $cat / $obj")
        info_dict[cat] = d.block[cat][lowercase.(d.block[cat][!,obj]) .== lk,:]
        if nrow(info_dict[cat]) == 0 delete!(info_dict,cat) end
    end
    return info_dict
end

# If a symbol is passed we access the block directly.
Base.getindex(d::DDL2_Dictionary,k::Symbol) = getindex(d.block,k)
Base.get(d::DDL2_Dictionary,k::Symbol,default) = get(d.block,k,default)

get_dic_name(d::DDL2_Dictionary) = d.block[:dictionary][:title][]
get_dic_namespace(d::DDL2_Dictionary) = "ddl2"  #single namespace

find_category(d::DDL2_Dictionary,dataname) = begin
    return String(split(dataname,'.')[1][2:end])
end

get_child_categories(d::DDL2_Dictionary,catname) = []

is_set_category(d::DDL2_Dictionary,catname) = false
is_loop_category(d::DDL2_Dictionary,catname) = true

find_object(d::DDL2_Dictionary,dataname) = begin
    if occursin(".",dataname)
        return String(split(dataname,".")[end])
    end
    return nothing
end

get_categories(d::DDL2_Dictionary) = d.block[:category][!,:id]
get_set_categories(d::DDL2_Dictionary) = []
get_loop_categories(d::DDL2_Dictionary) = get_categories(d)

get_keys_for_cat(d::DDL2_Dictionary,catname::String) = begin
    d[catname][:category_key][!,:name]
end

get_keys_for_cat(d::DDL2_Dictionary,catname::Symbol) = get_keys_for_cat(d,String(catname))

get_names_in_cat(d::DDL2_Dictionary,catname) = begin
    unique!(d.block[:item][d.block[:item].category_id .== catname,:name])
end

get_objs_in_cat(d::DDL2_Dictionary,catname) = begin
    unique!(d.block[:item][d.block[:item].category_id .== catname,:__object_id])
end

get_default(d::DDL2_Dictionary,dataname) = begin
    info = d[dataname]
    if haskey(info,:item_default) && :value in propertynames(info[:item_default])
        return info[:item_default].value[]
    end
    return missing
end

# Not available for DDL2
lookup_default(d::DDL2_Dictionary,dataname,packet) = missing

list_aliases(d::DDL2_Dictionary,name;include_self=false) = begin
    if include_self result = [name] else result = [] end
    alias_block = get(d[name],:item_aliases,nothing)
    if !isnothing(alias_block)
        append!(result, alias_block[!,:alias_name])
    end
    return result
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

has_drel_methods(d::DDL2_Dictionary) = true
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
    tablename = Symbol(split(first(names(new_info)),'.')[1][2:end])
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
    final_vals = Dict{Symbol,Any}((Symbol(split(x.first,'.')[end]),x.second) for x in new_vals)
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

#
#  All of the implicit are defined as caseless, so we use this information
#  as we might find ourselves comparing stuff in the future.
#
populate_implicits(all_tables) = begin
    cats = map(x->Symbol(split(x,'.')[1][2:end]),implicits)
    objs = map(x->Symbol(split(x,'.')[2]),implicits)
    for (cat,table) in all_tables
        if cat in cats
            target_name = objs[indexin([cat],cats)[]]
            if !(target_name in propertynames(table))
                rename!(table,(:__blockname=>target_name))
                #println("Added implicit value for $cat.$target_name")
            else
                table[target_name] = CaselessString.(table[target_name])
            end
        end
    end
end

add_cat_obj!(all_info) = begin
    catobj = split.(all_info[:item][!,:name],".")
    all_info[:item].category_id = [String(x[1][2:end]) for x in catobj]
    all_info[:item].__object_id = [String(x[2]) for x in catobj]
end

"""
as_data(d::DDL2_Dictionary)

Return an object `o` accessible using 
`o[attribute]` where `attribute`
is a ddl2 attribute.
"""
as_data(d::DDL2_Dictionary) = begin
    output = Dict{String,Any}()
    for c in keys(d.block)
        for o in propertynames(d.block[c])
            output["_$c.$o"] = d.block[c][!,o]
        end
    end
    return output
end

## Handling functions

# Methods for setting and retrieving evaluated functions
set_func!(d::DDL2_Dictionary,func_name::AbstractString,func_text::Expr,func_code) = begin
    d.func_defs[func_name] = func_code
    d.func_text[func_name] = func_text
    println("All funcs: $(keys(d.func_defs))")
end

get_func(d::DDL2_Dictionary,func_name::AbstractString) = d.func_defs[func_name]
get_func_text(d::DDL2_Dictionary,func_name::AbstractString) = d.func_text[func_name]
has_func(d::DDL2_Dictionary,func_name::AbstractString) = begin
    try
        d.func_defs[func_name]
    catch KeyError
        return false
    end
    return true
end

"""
Return functions defined in the dictionary. DDL2 does not have this
"""
get_dict_funcs(d::DDL2_Dictionary) = (nothing,[])

#== Extract the dREL text from the dictionary, if any
DDL2 holds all methods in a table indexed by method_id, with the
text listed in "_method_list.inline", the type of method given
in "_method_list.code" and the language in _method_list.language.

We say that 'Evaluation' == 'calculation' and accept only 'dREL'
for now.
==#
load_func_text(dict::DDL2_Dictionary,dataname::AbstractString,meth_type::String) =  begin
    if meth_type != "Evaluation" return "" end
    full_def = dict[dataname]
    meth_text = ""
    println("Full def: $full_def")
    if haskey(full_def,:item_methods)
        for one_row in eachrow(full_def[:item_methods])
            target = dict[:method_list][dict[:method_list].id .== one_row.method_id,:]
            if lowercase(target.code[]) == "calculation" &&
                lowercase(target.language[]) == "drel" meth_text = target.inline[]
            end
        end
    elseif haskey(full_def,:category_methods)
        for one_row in eachrow(full_def[:category_methods])
            target = dict[:method_list][dict[:method_list].id .== one_row.method_id,:]
            if lowercase(target.code[]) == "calculation" &&
                lowercase(target.language[]) == "drel" meth_text = target.inline[]
            end
        end
    end
    return meth_text
end

# Methods for setting and retrieving definition functions
has_default_methods(d::DDL2_Dictionary) = false

get_julia_type_name(cdic::DDL2_Dictionary,cat::AbstractString,obj::AbstractString) = begin
    definition = cdic[find_name(cdic,cat,obj)]
    type_index = definition[:item_type][!,:code][]
    all_types = cdic[:item_type_list]
    type_base = all_types[all_types[!,:code] .== type_index,:primitive_code][]
    # only strings...
    # println("DDL2 type for $cat/$obj is $type_base")
    if type_base != "uchar" return String,"Single" end
    return Symbol("CaselessString"),"Single"
end

get_container_type(cdic::DDL2_Dictionary,dataname) = "Single"

#
# **Output**
#
# DDL2 makes use of implicit values based on the block name. We
# ignore any columns contained in the 'implicit' const above.
#

show(io::IO,::MIME"text/cif",ddl2_dic::DDL2_Dictionary) = begin
    dicname = ddl2_dic[:dictionary].title[]
    write(io,"#")
    write(io,"""
##############################################################
#
#        $dicname (DDL2)
#
##############################################################\n""")
    write(io,"data_$dicname\n")
    implicit_info = get_implicit_list()
    top_level = ddl2_dic[:datablock]
    show_set(io,"datablock",top_level,implicits=implicit_info)
    top_level = ddl2_dic[:dictionary]
    show_set(io,"dictionary",top_level,implicits=implicit_info)
    # Now for the rest
    all_cats = sort(get_categories(ddl2_dic))
    for one_cat in all_cats
        cat_info = ddl2_dic[one_cat]
        show_one_def(io,one_cat,cat_info,implicits=implicit_info)
        items = get_names_in_cat(ddl2_dic,one_cat)
        for one_item in items
            show_one_def(io,one_item,ddl2_dic[one_item],implicits=implicit_info)
        end
    end
    # And the looped top-level stuff
    for c in [:item_units_conversion,:item_units_list,:item_type_list,:dictionary_history]
        if c in keys(ddl2_dic.block) && nrow(ddl2_dic[c]) > 0
            show_loop(io,String(c),ddl2_dic[c],implicits=implicit_info)
        end
    end
end

#
# We always want item.name to be printed.
#
get_implicit_list() = begin
    all_imps = map(x->x[2:end],implicits)
    filter!(x-> !(x in ["item.name","item.category_id",
                        "item_linked.parent_name"]),all_imps)
end
