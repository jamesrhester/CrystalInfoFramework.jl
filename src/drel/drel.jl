#== Definitions for running dREL code in Julia.
==#

export CategoryObject,find_target, ast_assign_types, ast_fix_indexing, to_julia_array
export fix_scope, get_attribute

"""The following models a dREL category object, that can be looped over,
with each iteration providing a new packet"""

struct CategoryObject
    datablock::cif_block_with_dict
    catname::String
    object_names::Vector{String}
    data_names::Vector{String}
    data_frame::DataFrame
    internal_object_names
    name_to_object
    object_to_name
    key_names
    is_looped
    have_vals
    key_index
    use_keys
end

CategoryObject(datablock,catname) = begin
    cifdic = datablock.dictionary
    object_names = [a for a in keys(cifdic) if lowercase(String(get(cifdic[a],"_name.category_id",[""])[1])) == lowercase(catname)]
    data_names = [String(cifdic[a]["_definition.id"][1]) for a in object_names]
    internal_object_names = [String(cifdic[a]["_name.object_id"][1]) for a in data_names]
    name_to_object = Dict(zip(data_names,internal_object_names))
    object_to_name = Dict(zip(internal_object_names,data_names))
    is_looped = String(get(cifdic[catname],"_definition.class",["Set"])[1]) == "Loop"
    have_vals = [k for k in data_names if k in keys(datablock)]
    use_keys = false
    key_index = []
    if is_looped
        key_names = cifdic[catname]["_category_key.name"]
        use_keys, key_names = create_keylists(key_names,have_vals)
    end
    actual_data = get_loop(datablock,have_vals[1])
    CategoryObject(datablock,catname,object_names,data_names,actual_data,internal_object_names,
        name_to_object,object_to_name,key_names,is_looped,have_vals,key_index,use_keys)
end

# This function creates lists of data names that can be used as keys of the category
create_keylists(key_names,have_vals) = begin
    have_keys = [k for k in key_names if k in have_vals]
    println("Found keys $have_keys")
    use_keys = true
    if length(have_keys) < length(key_names) #use all keys
        have_keys = have_vals
        use_keys = false
    end
    return use_keys, have_keys
end

# Allow access using a dictionary of object names

Base.getindex(c::CategoryObject,keydict) = begin
    pack = c.data_frame
    println("Loop is $pack")
    for pr in keydict
        k,v = pr
        println("Testing for $k == $v")
        pack = pack[ pack[Symbol(k)] .== v,:]
    end
    return pack
end

# We simply iterate over the data loop

Base.iterate(c::CategoryObject) = iterate(c.data_frame)
Base.iterate(c::CategoryObject,ci) = iterate(c.data_frame,ci)

#== The Tables.jl interface functions, commented out for now

Tables.istable(::Type{<:CategoryObject}) = true

Tables.rows(c::CategoryObject) = c

Tables.rowaccess(::Type{<:CategoryObject}) = true

Tables.schema(c::CategoryObject) = nothing

==#
