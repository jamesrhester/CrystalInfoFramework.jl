# CIF Dictionaries...built on CIF files
# Only DDLm dictionaries supported

export cifdic,get_by_cat_obj,assign_dictionary,get_julia_type,get_alias
export cif_block_with_dict,cifdic, abstract_cif_dictionary,cif_container_with_dict
export get_dictionary,get_datablock,find_category,get_categories,get_set_categories
export get_func,set_func!,has_func
export get_julia_type_name,get_loop_categories, get_dimensions, get_single_keyname
export CaselessString

abstract type abstract_cif_dictionary end

# Methods that should be instantiated by concrete types

Base.keys(d::abstract_cif_dictionary) = begin
    error("Keys function should be defined for $(typeof(d))")
end

Base.length(d::abstract_cif_dictionary) = begin
    return length(keys(d))
end

struct cifdic <: abstract_cif_dictionary
    block::NativeBlock    #the underlying CIF block
    definitions::Dict{String,String} #dataname -> blockname
    by_cat_obj::Dict{Tuple,String} #by category/object
    func_defs::Dict{String,Function}

    cifdic(b,d,c) = begin
        all_names = collect(keys(get_all_frames(b)))
        if !issubset(values(d),all_names)
            miss_vals = setdiff(values(d),all_names)
            error("""Cifdic: supplied definition lookup contains save frames that are
                    not present in the dictionary block: $miss_vals not in $all_names""")
        end
        if !issubset(values(c),all_names)
            error("""Cifdic: supplied cat-obj lookup contains save frames that are
                   not present in the dictionary block""")
        end
        return new(b,d,c,Dict())
    end
end

cifdic(c::NativeCif) = begin
    if length(keys(c))!= 1
        error("Error: Cif dictionary has more than one data block")
    end
    b = c[collect(keys(c))[1]]
    return cifdic(b)
end

cifdic(base_b::NativeBlock) = begin
    # importation first as it changes the block contents
    b = resolve_imports!(base_b)
    # create the definition names
    defs = get_all_frames(b)
    bnames = collect(keys(defs))
    match_dict = Dict()
    # create lookup tables for cat,obj if not a template dictionary
    cat_obj_dict = Dict()
    if String(b["_dictionary.class"][1]) != "Template"
        merge!(match_dict, Dict(String(lowercase(defs[k]["_definition.id"][1])) => k for k in bnames))
        # create all aliases
        extra_aliases = generate_aliases(defs)
        merge!(match_dict,extra_aliases)
        # now the information for cat/obj lookup
        defblocks = [(defs[k]["_name.category_id"][1],defs[k]["_name.object_id"][1],k) for k in bnames if "_name.category_id" in keys(defs[k]) && "_name.object_id" in keys(defs[k])]
        merge!(cat_obj_dict, Dict((lowercase.((String(s[1]),String(s[2]))),s[3]) for s in defblocks))
    else   # template dictionary, no cat/obj lookup, the save frame is the id
        merge!(match_dict, Dict(k=>k for k in bnames))
        merge!(match_dict, Dict(lowercase(k)=>k for k in bnames))
    end
    return cifdic(b,match_dict,cat_obj_dict)
end

cifdic(a::String) = cifdic(NativeCif(a))

# The index in a dictionary is the _definition.id or an alias
Base.getindex(cdic::cifdic,definition::String) = begin
    get_save_frame(cdic.block,cdic.definitions[lowercase(definition)])
end

Base.keys(cdic::cifdic) = begin
    keys(cdic.definitions)    
end

# We iterate over the definitions
Base.iterate(c::cifdic) = begin
    everything = collect(keys(c.definitions))
    if length(everything) == 0 return nothing
    end
    sort!(everything)
    return c[popfirst!(everything)],everything
end

Base.iterate(c::cifdic,s) = begin
    if length(s) == 0 return nothing
    end
    return c[popfirst!(s)],s
end

# Create an alias dictionary: b is actually the save frame collection
generate_aliases(b::NativeCif) = begin
    start_dict = Dict()
    for def in keys(b)
        if "_alias.definition_id" in keys(b[def])
            alias_names = lowercase.(String.(b[def]["_alias.definition_id"]))
            map(a->setindex!(start_dict,def,a),alias_names)
        end
    end
    return start_dict
end

get_by_cat_obj(c::cifdic,catobj::Tuple) = get_save_frame(c.block,c.by_cat_obj[lowercase.(catobj)])

find_category(c::cifdic,dataname::String) = begin
    block = c[dataname]
    catname = String(block["_name.category_id"][1])
end

get_categories(c::abstract_cif_dictionary) = begin
    cats = [x for x in keys(c) if String(get(c[x],"_definition.scope",["Item"])[])=="Category"]
    lowercase.([String(c[x]["_definition.id"][]) for x in cats])
end

get_set_categories(c::abstract_cif_dictionary) = begin
    all_cats = get_categories(c)
    [x for x in all_cats if String(get(c[x],"_definition.class",["Datum"])[]) == "Set"] 
end

get_loop_categories(c::abstract_cif_dictionary) = begin
    all_cats = get_categories(c)
    [x for x in all_cats if String(get(c[x],"_definition.class",["Datum"])[]) == "Loop"]
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
        obj = String(cat_keys[1])
    else
        alternate = get(definition,"_category.key_id",[])
        if length(alternate) == 0
            error("Category $c has no primitive key available")
        end
        obj = String(alternate[1])
    end
    objval = String(d[obj]["_name.object_id"][1])
end

set_func!(d::abstract_cif_dictionary,func_name::String,func_code) = begin
    d.func_defs[func_name] = func_code
end

get_func(d::abstract_cif_dictionary,func_name::String) = begin
    d.func_defs[func_name]
end

has_func(d::abstract_cif_dictionary,func_name::String) = begin
    try
        d.func_defs[func_name]
    catch KeyError
        return false
    end
    return true
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

#== We return a NativeBlock for further operations. While the
templated imports operate directly on the internal Dict entries,
it appears that the full imports create a copy ==#
resolve_imports!(b::NativeBlock) = begin
    c = get_all_frames(b) #dont care about actual non-save data
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
    return NativeBlock(new_c.contents,b.loop_names,b.data_values,b.original_file)
end

get_import_info(original_dir,import_entry) = begin
    # println("Now processing $one_entry")
    fixed = fix_url(String(import_entry["file"]),original_dir)
    url = URI(fixed)
    println("URI is $(url.scheme), $(url.path)")
    if url.scheme != "file"
        error("Non-file URI cannot be handled: $(url.scheme) from $(import_entry["file"])")
    end
    location = url.path
    block = String(import_entry["save"])
    mode = String(get(import_entry,"mode","Contents"))
    if_dupl = String(get(import_entry,"if_dupl","Exit"))
    if_miss = String(get(import_entry,"if_miss","Exit"))
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
                continue   # we will do this later
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
                    cached_dicts[location] = cifdic(location)
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
and in addition will reparent a children of the imported Head category to the new
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
            importee = cifdic(location)  #this will perform nested imports
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
                if lowercase(String(get(c[k],"_name.category_id",[""])[1])) == old_head
                    c[k]["_name.category_id"] = [native_cif_element(new_head)]
                end
            end
        end   #of one entry
    end  #of one _import.get statement
    return c
end

#== Adding dictionary information to a data block
==#

abstract type cif_container_with_dict <: cif_container{native_cif_element} end

#== Should always define the following methods
==#
get_dictionary(c::cif_container_with_dict) = begin
    error("get_dictionary not defined for concrete class!")
end

get_datablock(c::cif_container_with_dict) = begin
    error("get_datablock not defined for concrete class!")
end

struct cif_block_with_dict <: cif_container_with_dict
    data::NativeBlock
    dictionary::cifdic
end

assign_dictionary(c::NativeBlock,d::cifdic) = cif_block_with_dict(c,d)
get_dictionary(c::cif_block_with_dict) = c.dictionary
get_datablock(c::cif_block_with_dict) = c.data

Base.getindex(c::cif_container_with_dict,s::String) = begin
    as_string = get_datablock(c)[s]
    actual_type = get_julia_type(get_dictionary(c),s,as_string)
end

Base.iterate(c::cif_container_with_dict) = iterate(get_datablock(c))
Base.iterate(c::cif_container_with_dict,s) = iterate(get_datablock(c),s)

# As a dictionary is available, we return the loop that
# would contain the name, even if it is absent

get_loop(b::cif_container_with_dict,s::String) = begin
    dict = get_dictionary(b)
    category = dict[s]["_name.category_id"]
    all_names = [n for n in keys(dict) if get(dict[n],"_name.category_id",nothing) == category]
    #println("All names in category of $s: $all_names")
    loop_names = [l for l in all_names if l in keys(b)]
    if length(loop_names) == 0
        println("WARNING: Non-existent loop requested, category of $s")
    end
    #println("All names present in datafile: $loop_names")
    # Construct a data frame using Dictionary knowledge
    df = DataFrame()
    for n in loop_names
        obj_name = String(dict[n]["_name.object_id"][1])
        df[Symbol(lowercase(obj_name))] = b[n]
    end
    return df
end

# Anything not defined in the dictionary is invisible
Base.keys(c::cif_container_with_dict) = begin
    true_keys = lowercase.(collect(keys(get_datablock(c))))
    dnames = [d for d in keys(get_dictionary(c)) if lowercase(d) in true_keys]
    return dnames
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
                           "Dimension" => Integer,   
                           "Range"  => String, #TODO       
                           "Count"  => Integer,    
                           "Index"  => Integer,       
                           "Integer" => Integer,     
                           "Real" =>    Float64,        
                           "Imag" =>    Complex,  #really?        
                           "Complex" => Complex,     
                           # Symop       
                           # Implied     
                           # ByReference
                           "Array" => Array,
                           "Matrix" => Array,
                           "List" => Array{Any}
                           )

get_julia_type_name(cifdic,cat::String,obj::String) = begin
    definition = get_by_cat_obj(cifdic,(cat,obj))
    base_type = String(definition["_type.contents"][1])
    cont_type = String(get(definition,"_type.container",["Single"])[1])
    jl_base_type = type_mapping[base_type]
    return jl_base_type,cont_type
end

"""Convert to the julia type for a given category, object and String value.
This is clearly insufficient as it only handles one level of arrays."""
get_julia_type(cifdic,cat,obj,value) = begin
    julia_base_type,cont_type = get_julia_type_name(cifdic,cat,obj)
    change_func = (x->x)
    # println("Julia type for $base_type is $julia_base_type, converting $value")
    if julia_base_type == Integer
        change_func = (x -> map(y->parse(Int,y),x))
    elseif julia_base_type == Float64
        change_func = (x -> map(y->real_from_meas(y),x))
    elseif julia_base_type == Complex
        change_func = (x -> map(y->parse(Complex{Float64},y),x))   #TODO: SU on values
    elseif julia_base_type == String
        change_func = (x -> map(y->String(y),x))
    elseif julia_base_type == Symbol("CaselessString")
        change_func = (x -> map(y->CaselessString(y),x))
    end
    if cont_type == "Single"
        return change_func(value)
    elseif cont_type in ["Array","Matrix"]
        return map(change_func,value)
    else error("Unsupported container type $cont_type")   #we can do nothing
    end
end

get_julia_type(cifdic,dataname::String,value) = begin
    definition = cifdic[dataname]
    return get_julia_type(cifdic,String(definition["_name.category_id"][1]),String(definition["_name.object_id"][1]),value)
end

# return dimensions as an Array. Note that we do not handle
# asterisks, I think they are no longer allowed?
# The first dimension in Julia is number of rows, then number
# of columns. This is the opposite to dREL

get_dimensions(cifdic,cat,obj) = begin
    definition = get_by_cat_obj(cifdic,(cat,obj))
    dims = String(get(definition,"_type.dimension",["[]"])[1])
    final = eval(Meta.parse(dims))
    if length(final) > 1
        t = final[1]
        final[1] = final[2]
        final[2] = t
    end
    return final
end
    
real_from_meas(value) = begin
    as_string = String(value)
    if '(' in as_string
        return parse(Float64,as_string[1:findfirst(isequal('('),as_string)-1])
    end
    return parse(Float64,as_string)
end

Range(v::native_cif_element) = begin
    as_string = String(v)
    lower,upper = split(as_string,":")
    parse(Number,lower),parse(Number,upper)
end

#== This type of string compares as a caseless string
Most other operations are left undefined for now ==#

struct CaselessString <: AbstractString
    actual_string::String
end

Base.:(==)(a::CaselessString,b::AbstractString) = begin
    lowercase(a.actual_string) == lowercase(b)
end

Base.:(==)(a::AbstractString,b::CaselessString) = begin
    lowercase(a) == lowercase(b.actual_string)
end

Base.:(==)(a::CaselessString,b::CaselessString) = lowercase(a)==lowercase(b)

Base.iterate(c::CaselessString) = iterate(c.actual_string)
Base.iterate(c::CaselessString,s::Integer) = iterate(c.actual_string,s)
Base.ncodeunits(c::CaselessString) = ncodeunits(c.actual_string)
Base.isvalid(c::CaselessString,i::Integer) = isvalid(c.actual_string,i)
Base.codeunit(c::CaselessString) = codeunit(c.actual_string) 
