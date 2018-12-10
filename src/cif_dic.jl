# CIF Dictionaries...built on CIF files
# Only DDLm dictionaries supported

export cifdic,get_by_cat_obj,assign_dictionary,get_julia_type,get_alias

struct cifdic
    block::NativeBlock    #the underlying CIF block
    definitions::Dict{String,String}
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
    match_dict = Dict(String(lowercase(defs[k]["_definition.id"][1])) => k for k in bnames)
    extra_aliases = generate_aliases(defs)
    merge!(match_dict,extra_aliases)
    defblocks = [(defs[k]["_name.category_id"][1],defs[k]["_name.object_id"][1],k) for k in bnames if "_name.category_id" in keys(defs[k]) && "_name.object_id" in keys(defs[k])]
    cat_obj_dict = Dict((lowercase.((String(s[1]),String(s[2]))),s[3]) for s in defblocks)
    # add aliases TODO
    cifdic(b,match_dict,cat_obj_dict)
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

#== Adding dictionary information to a data block
==#

struct cif_block_with_dict <: cif_container
    data::NativeBlock
    dictionary::cifdic
end

assign_dictionary(c::NativeBlock,d::cifdic) = cif_block_with_dict(c,d)

Base.getindex(c::cif_block_with_dict,s::String) = begin
    true_key = c.dictionary.definitions[lowercase(s)]
    as_string = c.data[true_key]
    actual_type = get_julia_type(c.dictionary,s,as_string)
end

get_loop(b::cif_block_with_dict,s::String) = begin
    loop_names = [l for l in b.data.loop_names if s in l]
    # Construct a data frame using Dictionary knowledge
    df = DataFrame()
    for n in loop_names[1]
        df[Symbol(n)] = get_julia_type(b.dictionary,n,b.data.data_values[n])
    end
    return df
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



"""Convert to the julia type for a given category, object and String value.
This is clearly insufficient as it only handles one level of arrays."""
get_julia_type(cifdic,cat,obj,value) = begin
    definition = get_by_cat_obj(cifdic,(cat,obj))
    base_type = String(definition["_type.contents"][1])
    cont_type = String(get(definition,"_type.container",["Single"])[1])
    change_func = (x->x)
    julia_base_type = type_mapping[base_type]
    println("Julia type for $base_type is $julia_base_type, converting $value")
    if julia_base_type == Integer
        change_func = (x -> map(y->parse(Int,y),x))
    elseif julia_base_type == Float64
        change_func = (x -> map(y->real_from_meas(y),x))
    elseif julia_base_type == Complex
        change_func = (x -> map(y->parse(Complex{Float64},y),x))   #TODO: SU on values
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
        return parse(Float64,as_string[:findfirst(isequal("("),as_string)-1])
    end
    return parse(Float64,as_string)
end

Range(v::native_cif_element) = begin
    as_string = String(v)
    lower,upper = split(as_string,":")
    parse(Number,lower),parse(Number,upper)
end


