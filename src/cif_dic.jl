# CIF Dictionaries...built on CIF files
# Only DDLm dictionaries supported

export cifdic,get_by_cat_obj,assign_dictionary,get_julia_type,get_alias

struct cifdic
    block::NativeBlock    #the underlying CIF block
    definitions::Dict{String,String} #dataname -> blockname
    by_cat_obj::Dict{Tuple,String} #by category/object
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
        return new(b,d,c)
    end
end

cifdic(c::NativeCif) = begin
    if length(keys(c))!= 1
        error("Error: Cif dictionary has more than one data block")
    end
    b = c[collect(keys(c))[1]]
    # now create the definition names
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
    resolve_imports!(cifdic(b,match_dict,cat_obj_dict))
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

#== Resolve imports
This routine will substitute all _import.get statements with the imported dictionary. Generally
the only reason that you would not do this is if you are editing the dictionary rather than
using it.
==#

#== Turn a possibly relative URL into an absolute one. Will probably fail with pathological
URLs containing colons early on ==#

fix_url(s::String,parent::String) = begin
    try
        p = URI(s)
    catch   #something wrong
        if s[1]=='/'
            return "file:"*s
        elseif s[1]=="."
            return "file://"*parent*s[2:end]
        else
            return "file://"*parent*"/"*s
        end
    end
    return s
end

resolve_imports!(c::cifdic) = begin
    cached_dicts = Dict()   #to save reading twice
    for one_block in c
        if !haskey(one_block,"_import.get")
            continue
        end
        original_dir = dirname(c.block.original_file)
        import_table = one_block["_import.get"][1]
        import_def = nothing   #define it in the right scope
        for one_entry in import_table
            # println("Now processing $one_entry")
            url = URI(fix_url(String(one_entry["file"]),original_dir))
            if url.scheme != "file"
                error("Non-file URI cannot be handled: $(one_entry[file])")
            end
            location = url.path
            block = String(one_entry["save"])
            mode = String(get(one_entry,"mode","Contents"))
            if mode == "Full"
                println("WARNING: Full mode import not implemented yet; skipping $location")
                continue
            end
            if_dupl = String(get(one_entry,"if_dupl","Exit"))
            if_miss = String(get(one_entry,"if_miss","Exit"))
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
            # now merge it all in
            if mode == "Contents"
                #println("Now merging $one_block and $import_def")
                merge!(combiner,one_block,import_def)
            elseif mode == "Full"
                println("WARNING: full mode imports not supported yet, ignored")
            end
        end   #of import list cycle
        delete!(one_block,"_import.get")
    end
    return c
end

#== Adding dictionary information to a data block
==#

struct cif_block_with_dict <: cif_container{native_cif_element}
    data::NativeBlock
    dictionary::cifdic
end

assign_dictionary(c::NativeBlock,d::cifdic) = cif_block_with_dict(c,d)

Base.getindex(c::cif_block_with_dict,s::String) = begin
    as_string = c.data[s]
    actual_type = get_julia_type(c.dictionary,s,as_string)
end

# As a dictionary is available, we return the loop that
# would contain the name, even if it is absent

get_loop(b::cif_block_with_dict,s::String) = begin
    category = b.dictionary[s]["_name.category_id"]
    all_names = [n for n in keys(b.dictionary) if get(b.dictionary[n],"_name.category_id",nothing) == category]
    #println("All names in category of $s: $all_names")
    loop_names = [l for l in all_names if l in keys(b)]
    if length(loop_names) == 0
        error("Non-existent loop requested, same category as $s")
    end
    #println("All names present in datafile: $loop_names")
    # Construct a data frame using Dictionary knowledge
    df = DataFrame()
    for n in loop_names
        obj_name = String(b.dictionary[n]["_name.object_id"][1])
        df[Symbol(lowercase(obj_name))] = b[n]
    end
    return df
end

# Anything not defined in the dictionary is invisible
Base.keys(c::cif_block_with_dict) = begin
    true_keys = lowercase.(collect(keys(c.data)))
    dnames = [d for d in keys(c.dictionary) if lowercase(d) in true_keys]
    return dnames
end
#==
The dREL type machinery. Defined that take a string
as input and return an object of the appropriate type
==#

#== Type annotation ==#
const type_mapping = Dict( "Text" => String,        
                           "Code" => String,                                                
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

get_julia_type_name(cifdic,cat,obj) = begin
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


