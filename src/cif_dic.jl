# CIF Dictionaries...built on CIF files
# Only DDLm dictionaries supported

export cifdic,get_by_cat_obj

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
    cat_obj_dict = Dict((lowercase.((String(s["_name.category_id"]),String(s["_name.object_id"]))),get_block_code(s)) for s in get_all_frames(b))
    cifdic(b,match_dict,cat_obj_dict)
end

cifdic(a::AbstractString) = cifdic(cif(a))

# The index in a dictionary is the _definition.id
Base.getindex(cdic::cifdic,definition::AbstractString) = begin
    get_save_frame(cdic.block,cdic.definitions[definition])
end

get_by_cat_obj(c::cifdic,catobj::Tuple) = get_save_frame(c.block,c.by_cat_obj[lowercase.(catobj)])

#==
The dREL type machinery. Defined that take a string
as input and return an object of the appropriate type
==#

Range(v::cif_value_tp_ptr) = begin
    as_string = String(v)
    lower,upper = split(as_string,":")
    parse(Number,lower),parse(Number,upper)
end


