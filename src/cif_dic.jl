# CIF Dictionaries...built on CIF files
# Only DDLm dictionaries supported
struct cifdic
    block::cif_block    #the underlying CIF block
    definitions::Dict{AbstractString,AbstractString}
    cifdic(b,d) = begin
        if Set(values(d))⊂keys(block)
            return new(b,d)
        else
            error("Cifdic: supplied dictionary contains keys that are
            not present in the dictionary block")
        end
end

cifdic(c::cif) = begin
    if len(keys(c))!= 1
        error("Error: Cif dictionary has more than one data block")
    end
    b = c[keys(c)[0]]
    # now create the definition names
    match_dict = Dict(s['_definition.id'] => get_frame_code(s) for s in get_all_frames(b))
    cifdic(b,match_dict)
end

# The index in a dictionary is the _definition.id
getindex(cdic::cifdic,definition::AbstractString) = begin
    cdic.block.get_save_frame(cdic.definitions[definition])
end
