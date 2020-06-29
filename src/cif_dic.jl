# CIF Dictionaries...built on CIF files
# Only DDLm dictionaries supported

export Cifdic,get_by_cat_obj,assign_dictionary,get_julia_type,get_alias, is_alias
export cif_block_with_dict, abstract_cif_dictionary,cif_container_with_dict
export get_dictionary,get_datablock,find_category,get_categories,get_set_categories
export get_typed_datablock
export translate_alias,list_aliases
export find_object
export get_single_key_cats
export get_names_in_cat,get_linked_names_in_cat,get_keys_for_cat
export get_objs_in_cat
export get_dict_funcs                   #List the functions in the dictionary
export get_parent_category,get_child_categories
export get_func,set_func!,has_func
export get_def_meth,get_def_meth_txt    #Methods for calculating defaults
export get_julia_type_name,get_loop_categories, get_dimensions, get_single_keyname
export get_ultimate_link
export get_default

abstract type abstract_cif_dictionary end

# Methods that should be instantiated by concrete types

Base.keys(d::abstract_cif_dictionary) = begin
    error("Keys function should be defined for $(typeof(d))")
end

Base.length(d::abstract_cif_dictionary) = begin
    return length(keys(d))
end

# TODO: add more universal methods here

# Read in ddl2 dictionaries as well, uniform interface.
# include("ddl2_dic.jl")
#==
A Cifdic is a DDLm dictionary. The following semantics are important:
(1) Importation. A DDLm dictionary can import parts of definitions,
or complete dictionaries in order to describe the whole semantic space
(2) Parent-child. An object name may be referenced as if it were
part of the parent category; so if <c> is a child of <p>, and <q> is
an object in <c> (that is, "_c.q" is the dataname), then "p.q" refers
to the same item as "c.q" in dREL methods. It is not the case that
"_p.q" is a defined dataname.  The code here therefore implements only
the methods needed to find parents and children. 
==#

struct Cifdic <: abstract_cif_dictionary
    block::FullBlock    #the underlying CIF block
    definitions::Dict{String,String} #dataname -> blockname
    by_cat_obj::Dict{Tuple,String} #by category/object
    parent_lookup::Dict{String,String} #child -> parent
    func_defs::Dict{String,Function}
    func_text::Dict{String,Expr} #unevaluated Julia code
    def_meths::Dict{Tuple,Function}
    def_meths_text::Dict{Tuple,Expr}
end

Cifdic(b,d,c,parents) = begin
    all_names = collect(keys(get_frames(b)))
    if !issubset(values(d),all_names)
        miss_vals = setdiff(values(d),all_names)
        error("""Cifdic: supplied definition lookup contains save frames that are
                        not present in the dictionary block: $miss_vals not in $all_names""")
    end
    if !issubset(values(c),all_names)
        error("""Cifdic: supplied cat-obj lookup contains save frames that are
                       not present in the dictionary block""")
    end
    Cifdic(b,d,c,parents,Dict(),Dict(),Dict(),Dict())
end


Cifdic(c::NativeCif) = begin
    if length(keys(c))!= 1
        error("Error: Cif dictionary has more than one data block")
    end
    return Cifdic(first(c).second)
end

Cifdic(base_b::FullBlock) = begin
    # importation first as it changes the block contents
    b = resolve_imports!(base_b)
    # create the definition names
    defs = get_frames(b)
    bnames = collect(keys(defs))
    match_dict = Dict()
    # create lookup tables for cat,obj if not a template dictionary
    cat_obj_dict = Dict()
    parent_dict = Dict()
    if b["_dictionary.class"][1] != "Template"
        merge!(match_dict, Dict(lowercase(defs[k]["_definition.id"][1]) => k for k in bnames))
        # create all aliases
        extra_aliases = generate_aliases(defs)
        merge!(match_dict,extra_aliases)

        # now the information for cat/obj lookup
        defblocks = [(defs[k]["_name.category_id"][1],defs[k]["_name.object_id"][1],k) for k in bnames if "_name.category_id" in keys(defs[k]) && "_name.object_id" in keys(defs[k])]
        merge!(cat_obj_dict, Dict((lowercase.((s[1],s[2])),s[3]) for s in defblocks))
        # now find the parents for every category
        all_cats = [s for s in keys(defs) if get(defs[s],"_definition.scope",["Item"])[1]=="Category"]
        all_parents = [get(defs[c],"_name.category_id",[c])[1] for c in all_cats]
        parent_dict = Dict(zip(lowercase.([defs[c]["_definition.id"][1] for c in all_cats]),lowercase.(all_parents)))
    else   # template dictionary, no cat/obj lookup, the save frame is the id
        merge!(match_dict, Dict(k=>k for k in bnames))
        merge!(match_dict, Dict(lowercase(k)=>k for k in bnames))
    end
    return Cifdic(b,match_dict,cat_obj_dict,parent_dict)
end

Cifdic(a::String;verbose=false) = Cifdic(NativeCif(a,verbose=verbose))

# The index in a dictionary is the _definition.id or an alias
Base.getindex(cdic::Cifdic,definition::String) = begin
    get_save_frame(cdic.block,cdic.definitions[lowercase(definition)])
end

Base.get(cdic::Cifdic,definition::String,default) = begin
    try
        return cdic[definition]
    catch KeyError
        return default
    end
end
        
Base.keys(cdic::Cifdic) = begin
    keys(cdic.definitions)    
end

Base.haskey(cdic::Cifdic,k::String) = begin
    haskey(cdic.definitions,k)
end

# We iterate over the definitions
Base.iterate(c::Cifdic) = begin
    everything = collect(keys(c.definitions))
    if length(everything) == 0 return nothing
    end
    sort!(everything)
    return c[popfirst!(everything)],everything
end

Base.iterate(c::Cifdic,s) = begin
    if length(s) == 0 return nothing
    end
    return c[popfirst!(s)],s
end

# Create an alias dictionary: b is actually the save frame collection
generate_aliases(b::NativeCif;alias_att = "_alias.definition_id") = begin
    start_dict = Dict()
    for def in keys(b)
        if alias_att in keys(b[def])
            alias_names = lowercase.(b[def][alias_att])
            map(a->setindex!(start_dict,def,a),alias_names)
        end
    end
    return start_dict
end

list_aliases(b::Cifdic,n;include_self=false) = begin
    starter = []
    if include_self push!(starter,b[n]["_definition.id"][]) end
    return append!(starter, get(b[n],"_alias.definition_id",[]))
end

# Return the canonical name of `n`
translate_alias(b::Cifdic,n) = begin
    return b[n]["_definition.id"][]
end

"""
Determine whether or not dataname d is a definition or simply an alias
"""
is_alias(c::Cifdic,d::String) = begin
    if !haskey(c,d) return false end
    c[d]["_definition.id"][1] != d
end

get_by_cat_obj(c::Cifdic,catobj::Tuple) = begin
    if get(c[catobj[1]],"_definition.class",["Set"])[1] == "Loop"
        children = get_child_categories(c,catobj[1])
        for one_child in children
            extra_objects = lowercase.([c[k]["_name.object_id"][1] for k in get_names_in_cat(c,one_child)])
            if lowercase(catobj[2]) in extra_objects
                return get_save_frame(c.block,c.by_cat_obj[one_child,lowercase(catobj[2])])
            end
        end
    end
    get_save_frame(c.block,c.by_cat_obj[lowercase.(catobj)])
end

find_category(c::Cifdic,dataname::String) = begin
    block = c[dataname]
    catname = lowercase(block["_name.category_id"][1])
end

find_object(c::Cifdic,dataname::String) = begin
    block = c[dataname]
    objname = lowercase(block["_name.object_id"][1])
end

get_categories(c::Cifdic) = begin
    cats = [x for x in keys(c) if get(c[x],"_definition.scope",["Item"])[]=="Category"]
    lowercase.([c[x]["_definition.id"][] for x in cats])
end

get_names_in_cat(c::abstract_cif_dictionary,cat::String;aliases=false) = begin
    names = [n for n in keys(c) if find_category(c,n) == lowercase(cat)]
    if aliases
        alias_srch = copy(names)
        for n in alias_srch
            append!(names,list_aliases(c,n))
        end
    end
    return names
end

get_objs_in_cat(c::abstract_cif_dictionary,cat::String) = begin
    names = get_names_in_cat(c,cat)
    [find_object(c,n) for n in names]
end

get_keys_for_cat(c::Cifdic,cat::String;aliases=false) = begin
    loop_keys = get(c[cat],"_category_key.name",[])
    key_aliases = []
    if aliases
        for k in loop_keys
            append!(key_aliases,list_aliases(c,k))
        end
    end
    append!(key_aliases,loop_keys)
    return key_aliases
end

get_linked_names_in_cat(c::abstract_cif_dictionary,cat::String) = begin
    names = [n for n in get_names_in_cat(c,cat) if length(get(c[n],"_name.linked_item_id",[]))==1]
    names = [n for n in names if get(c[n],"_type.purpose",["Datum"])[1] != "SU"]
    return names
end

"""
Follow linked data names
"""
get_link_groups(c::Cifdic) = begin
end

get_set_categories(c::abstract_cif_dictionary) = begin
    all_cats = get_categories(c)
    [x for x in all_cats if get(c[x],"_definition.class",["Datum"])[] == "Set"] 
end

get_loop_categories(c::abstract_cif_dictionary) = begin
    all_cats = get_categories(c)
    [x for x in all_cats if get(c[x],"_definition.class",["Datum"])[] == "Loop"]
end

"""
Return the names of all functions defined in the dictionary, together with the function category
"""
get_dict_funcs(dict::abstract_cif_dictionary) = begin
    func_cat = [a for a in keys(dict) if get(dict[a],"_definition.class",["Datum"])[1] == "Functions"]
    if length(func_cat) > 0
        func_catname = lowercase(dict[func_cat[1]]["_name.object_id"][1])
        all_funcs = [a for a in keys(dict) if lowercase(dict[a]["_name.category_id"][1]) == func_catname]
        all_funcs = lowercase.([dict[a]["_name.object_id"][1] for a in all_funcs])
    else
        all_funcs = []
    end
    return func_catname,all_funcs
end

get_parent_category(c::Cifdic,child) = begin
    c.parent_lookup[child]
end

get_child_categories(c::abstract_cif_dictionary,parent) = begin
    [d for d in get_categories(c) if get_parent_category(c,d) == lowercase(parent)]
end

    
#== Get the object part of a single dataname that acts as a key
==#
get_single_keyname(d::abstract_cif_dictionary,c::String) = begin
    definition = d[c]
    cat_keys = get(definition,"_category_key.name",[])
    obj = missing
    if length(cat_keys) == 0
        error("Category $c has no key datanames defined")
    end
    if length(cat_keys) == 1
        obj = cat_keys[1]
    else
        alternate = get(definition,"_category.key_id",[])
        if length(alternate) == 0
            error("Category $c has no primitive key available")
        end
        obj = alternate[1]
    end
    objval = d[obj]["_name.object_id"][1]
end

"""
Return a list (category,keyname) for all categories that have
a single key, where that key is not a child key of another
category. This latter case corresponds to a split single
category.
"""
get_single_key_cats(d::abstract_cif_dictionary) = begin
    candidates = get_loop_categories(d)
    result = [x for x in candidates if length(get(d[x],"_category_key.name",[]))==1]
    keynames = [(r,first(d[r]["_category_key.name"])) for r in result]
    keynames = [(k[1],k[2]) for k in keynames if length(get(d[k[2]],"_name.linked_item_id",[]))==0]
    return keynames
end

"""
Find the ultimately-linked dataname, if there is one. Protect against
simple self-referential loops.
"""
get_ultimate_link(d::abstract_cif_dictionary,dataname::String) = begin
    if haskey(d,dataname)
        #println("Searching for ultimate value of $dataname")
        if haskey(d[dataname],"_name.linked_item_id") &&
            d[dataname]["_name.linked_item_id"][1] != dataname
            return get_ultimate_link(d,d[dataname]["_name.linked_item_id"][1])
        end
    end
    return dataname
end

# get the default value specified for s

get_default(b::abstract_cif_dictionary,s::String) = begin
    get(b[s],"_enumeration.default",[missing])[1]
end
    
# Methods for setting and retrieving evaluated functions
set_func!(d::abstract_cif_dictionary,func_name::String,func_text::Expr,func_code) = begin
    d.func_defs[func_name] = func_code
    d.func_text[func_name] = func_text
    println("All funcs: $(keys(d.func_defs))")
end

get_func(d::abstract_cif_dictionary,func_name::String) = d.func_defs[func_name]
get_func_text(d::abstract_cif_dictionary,func_name::String) = d.func_text[func_name]
has_func(d::abstract_cif_dictionary,func_name::String) = begin
    try
        d.func_defs[func_name]
    catch KeyError
        return false
    end
    return true
end

# Methods for setting and retrieving definition functions

get_def_meth(d::abstract_cif_dictionary,func_name::String,ddlm_attr::String) = d.def_meths[(func_name,ddlm_attr)]
get_def_meth_txt(d::abstract_cif_dictionary,func_name::String,ddlm_attr::String) = d.def_meths_text[(func_name,ddlm_attr)]

set_func!(d::abstract_cif_dictionary,func_name::String,ddlm_attr::String,func_text::Expr,func_code) = begin
    d.def_meths[(func_name,ddlm_attr)] = func_code
    d.def_meths_text[(func_name,ddlm_attr)] = func_text
end

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

#== We return a FullBlock for further operations. While the
templated imports operate directly on the internal Dict entries,
it appears that the full imports create a copy ==#
resolve_imports!(b::nested_cif_container) = begin
    c = get_frames(b) #dont care about actual non-save data
    imports = [c[a] for a in keys(c) if haskey(c[a],"_import.get")]
    if length(imports) == 0
        return b
    end
    resolve_templated_imports!(c,imports)
    new_c = resolve_full_imports!(c,imports)
    # remove all import commands
    for i in imports
        delete!(i,"_import.get")
    end
    return FullBlock(new_c.contents,get_loop_names(b),get_data_values(b),get_source_file(b))
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

resolve_templated_imports!(c::NativeCif,temp_blocks) = begin
    cached_dicts = Dict()   #to save reading twice
    original_dir = dirname(c.original_file)
    for one_block in temp_blocks
        import_table = one_block["_import.get"][1]
        import_def = nothing   #define it in the right scope
        for one_entry in import_table
            (location,block,mode,if_dupl,if_miss) = get_import_info(original_dir,one_entry)
            if mode == "Full"
                continue   # these are done separately
            end
            # define a combiner function
            combiner(a,b) = begin
                if if_dupl == "Exit"
                    error("Key duplicated when importing from $block at $location: $a and $b")
                elseif if_dupl == "Ignore"
                    return a
                elseif if_dupl == "Replace"
                    return b
                end
            end
            # Now carry out the import
            if !(location in keys(cached_dicts))
                #println("Now trying to import $location")
                try
                    cached_dicts[location] = Cifdic(location)
                catch y
                    #println("Error $y, backtrace $(backtrace())")
                    if if_miss == "Exit"
                        error("Unable to find import for $location")
                    else
                        continue
                    end
                end
            end
            # now find the data block
            try
                import_def = cached_dicts[location][block]
            catch
                if if_miss == "Exit"
                    error("When importing frame: Unable to find save frame $block in $location")
                else
                    continue
                end
            end
            #println("Now merging $block into $(get(one_block,"_definition.id","?"))")
            merge!(combiner,one_block,import_def)
        end   #of import list cycle
    end #of loop over blocks
    return c
end

#== A full import of Head into Head will add all definitions from the imported dictionary,
and in addition will reparent all children of the imported Head category to the new
Head category.  We first merge the two sets of save frames, and then fix the parent category
of any definitions that had the old head category as parent. Note that the NativeCif
object passed to us is just the save frames from a dictionary.
==#
resolve_full_imports!(c::NativeCif,imp_blocks) = begin
    original_dir = dirname(c.original_file)
    for into_block in imp_blocks
        import_table = into_block["_import.get"][1]
        import_def = nothing   #define it in the right scope
        for one_entry in import_table
            (location,block,mode,if_dupl,if_miss) = get_import_info(original_dir,one_entry)
            if mode == "Contents"
                continue   # we have done this
            end
            if into_block["_definition.class"][1] != "Head"
                println("WARNING: full mode imports into non-head categories not supported, ignored")
                continue
            end
            importee = Cifdic(location)  #this will perform nested imports
            importee_head = importee[block]
            if importee_head["_definition.class"][1] != "Head"
                println("WARNING: full mode imports of non-head categories not supported, ignored")
                continue
            end
            # define a combiner function
            combiner(a,b) = begin
                if if_dupl == "Exit"
                    error("Block duplicated when importing from $location: $a and $b")
                elseif if_dupl == "Ignore"
                    return a
                elseif if_dupl == "Replace"
                    return b
                end
            end
            # store the name of the old head category...and delete
            old_head = lowercase(importee_head["_name.object_id"][1])
            new_head = into_block["_name.object_id"][1]
            delete!(importee.block.save_frames,block)
            # merge the save frames
            println("Before merging, $(length(c.contents)) save frames")
            merge!(combiner,c.contents,importee.block.save_frames)
            println("After merging, $(length(c.contents)) save frames")
            # reparent those blocks that have the old head category as parent
            for k in keys(c)
                if lowercase(get(c[k],"_name.category_id",[""])[1]) == old_head
                    c[k]["_name.category_id"] = [new_head]
                end
            end
        end   #of one entry
    end  #of one _import.get statement
    return c
end


