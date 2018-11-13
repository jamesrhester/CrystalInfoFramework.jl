# CIF Dictionaries...built on CIF files
# Only DDLm dictionaries supported

export cifdic,get_by_cat_obj,assign_dictionary,get_dataname_type

struct cifdic
    block::cif_block    #the underlying CIF block
    definitions::Dict{AbstractString,AbstractString}
    by_cat_obj::Dict{Tuple,AbstractString} #by category/object
    cifdic(b,d,c) = begin
        if !issubset(values(d),get_block_code.(get_all_frames(b)))
            error("""Cifdic: supplied definition lookup contains save frames that are
                    not present in the dictionary block""")
        end
        if !issubset(values(c),get_block_code.(get_all_frames(b)))
            error("""Cifdic: supplied cat-obj lookup contains save frames that are
                   not present in the dictionary block""")
        end
        return new(b,d,c)
    end
end

cifdic(c::cif) = begin
    if length(keys(c))!= 1
        error("Error: Cif dictionary has more than one data block")
    end
    b = c[keys(c)[1]]
    # now create the definition names
    match_dict = Dict(String(s["_definition.id"]) => get_block_code(s) for s in get_all_frames(b))
    defblocks = [(s["_name.category_id"],s["_name.object_id"],s) for s in get_all_frames(b) if "_name.category_id" in keys(s) && "_name.object_id" in keys(s)]
    cat_obj_dict = Dict((lowercase.((String(s[1]),String(s[2]))),get_block_code(s[3])) for s in defblocks)
    cifdic(b,match_dict,cat_obj_dict)
end

cifdic(a::AbstractString) = cifdic(cif(a))


# The index in a dictionary is the _definition.id
Base.getindex(cdic::cifdic,definition::AbstractString) = begin
    get_save_frame(cdic.block,cdic.definitions[definition])
end

get_by_cat_obj(c::cifdic,catobj::Tuple) = get_save_frame(c.block,c.by_cat_obj[lowercase.(catobj)])

#== Adding dictionary information to a data block
==#

struct cif_block_with_dict <: cif_container
    handle::cif_container_tp_ptr
    cif_handle::cif
    dictionary::cifdic
end

assign_dictionary(c::cif_block,d::cifdic) = cif_block_with_dict(c.handle,c.cif_handle,d)

"""If we have a dictionary, we can determine the dataname type"""
get_dataname_type(b::cif_block_with_dict,d::AbstractString) = begin
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

get_julia_type(cifdic,dataname::AbstractString) = begin
    definition = cifdic[dataname]
    return get_julia_type(cifdic,String(definition["_name.category_id"]),String(definition["_name.object_id"]))
end

Range(v::cif_value_tp_ptr) = begin
    as_string = String(v)
    lower,upper = split(as_string,":")
    parse(Number,lower),parse(Number,upper)
end


