# CIF Dictionaries...built on CIF files
# Only DDLm dictionaries supported

export cifdic,get_by_cat_obj,assign_dictionary,get_dataname_type,get_alias

struct cifdic
    block::NativeBlock    #the underlying CIF block
    definitions::Dict{String,String}
    by_cat_obj::Dict{Tuple,String} #by category/object
    cifdic(b,d,c) = begin
        all_names = collect(keys(b))
        if !issubset(values(d),all_names)
            error("""Cifdic: supplied definition lookup contains save frames that are
                    not present in the dictionary block""")
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
    b = c[keys(c)[1]]
    # now create the definition names
    defs = get_all_frames(b)
    bnames = collect(keys(defs))
    match_dict = Dict(String(defs[k]["_definition.id"]) => k for k in bnames)
    defblocks = [(defs[k]["_name.category_id"],defs[k]["_name.object_id"],k) for k in bnames if "_name.category_id" in keys(defs[k]) && "_name.object_id" in keys(defs[k])]
    cat_obj_dict = Dict((lowercase.((String(s[1]),String(s[2]))),s[3]) for s in defblocks)
    # add aliases TODO
    cifdic(b,match_dict,cat_obj_dict)
end

cifdic(a::String) = cifdic(NativeCif(a))

# The index in a dictionary is the _definition.id or an alias
Base.getindex(cdic::cifdic,definition::String) = begin
    get_save_frame(cdic.block,cdic.definitions[definition])
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

# Add aliases to our lookup dictionary
generate_aliases(c::cifdic,name::String) = begin
    if name in keys(c.definitions) return c.definitions[name] end
    # find the name in all definitions
    aliases = nothing
    for def in values(c.definitions)
        try
            aliases = get_loop(c[def],"_alias.definition_id")
        catch
            continue
        end
        alias_names = [lowercase(String(a["_alias.definition_id"])) for a in aliases]
        if lowercase(name) in alias_names return def end
    end
    return nothing
end

get_by_cat_obj(c::cifdic,catobj::Tuple) = get_save_frame(c.block,c.by_cat_obj[lowercase.(catobj)])

#== Adding dictionary information to a data block
==#

struct cif_block_with_dict <: cif_container
    data::NativeBlock
    dictionary::cifdic
end

assign_dictionary(c::NativeBlock,d::cifdic) = cif_block_with_dict(c,d)

"""If we have a dictionary, we can determine the dataname type"""
get_dataname_type(b::cif_block_with_dict,d::String) = begin
    t = get_julia_type(b.dictionary,d)
    if typeof(t) == Expr
        return eval(t)
    else
        return t
    end
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


"""Get the julia type for a given category and object"""
get_julia_type(cifdic,cat,obj) = begin
    definition = get_by_cat_obj(cifdic,(cat,obj))
    base_type = String(definition["_type.contents"])
    cont_type = String(get(definition,"_type.container","Single"))
    julia_base_type = get(type_mapping,base_type,Any)
    final_type = julia_base_type
    if cont_type == "Single"
        return final_type
    end
    dims = String(definition["_type.dimension"])
    act_dims = parse.(Int,split(dims[2:end-1],","))
    final_type = :($(type_mapping[cont_type]){$julia_base_type,$(length(act_dims))})
    println("complex type $cont_type, dims $dims mapped to $final_type")
    #println("with type $(typeof(final_type))")
    return final_type
end

get_julia_type(cifdic,dataname::String) = begin
    definition = cifdic[dataname]
    return get_julia_type(cifdic,String(definition["_name.category_id"]),String(definition["_name.object_id"]))
end

Range(v::native_cif_element) = begin
    as_string = String(v)
    lower,upper = split(as_string,":")
    parse(Number,lower),parse(Number,upper)
end


