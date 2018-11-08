#== Definitions for running dREL code in Julia
==#

"""The following models a dREL category object, that can be looped over,
with each iteration providing a new packet"""

struct CategoryObject
    datablock::cif_block
    catname::AbstractString
    cifdic::cif_dic
    object_names::Vector{AbstractString}
    data_names::Vector{AbstractString}
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
    cifdic = datablock.cifdic
    object_names = [a for a in keys(cifdic) if cifdic[a]["_name.category_id"] == catname]
    data_names = [cifdic[a]["_definition.id"] for a in object_names]
    internal_object_names = [cifdic[a]["_name.object_id"] for a in data_names]
    name_to_object = Dict(zip(data_names,internal_object_names))
    object_to_name = Dict(zip(internal_object_names,data_names))
    key_names = get(cifdic[catname],"_category_key.name",[])
    is_looped = get(cifdic[catname],"_definition.class","Set") == "Loop"
    have_vals = [k for k in data_names if k in datablock]
    use_keys = false
    key_index = []
    if is_looped
        use_keys, key_index = create_keylists(key_names,have_vals,datablock)
    end
    CategoryObject(datablock,catname,cifdic,object_names,data_names,internal_object_names,
        name_to_object,object_to_name,key_names,is_looped,have_vals,key_index,use_keys)
end

# This function creates lists of data names that can be used as keys of the category
create_keylists(key_names,have_vals,datablock) = begin
    have_keys = [k for k in key_names if k in have_vals]
    if length(have_keys) == length(key_names)
        keylists = [datablock[k] for k in key_names]
        use_keys = true
    else  #use all data names in the category
        keylists = [datablock[k] for k in have_vals]
        use_keys = false
    end
    if length(key_names) == 1
        return use_keys,keylists[1]   #first element
    else
        return use_keys,zip(keylists...)
    end
end

# Allow access using a dictionary of object names
Base.getindex(c::CategoryObject,keydict) = begin
    k = keys(keydict)
    for one_pack in c
        vals = [(keydict[i],one_pack[i]) for i in k]
        f = filter(a[1]==a[2],vals)
        if length(f)==length(k)  # all matched
            return one_pack
        end
    end
    return nothing
end

Base.iterate(c::CategoryObject) = begin
    probe_name = c.keylists[1]
    l = get_loop(c.datablock,probe_name)
    iterate(l)
end

Base.iterate(c::CategoryObject,ci) = begin
    iterate(ci)
end

#== Type annotation ==#
const type_mapping = Dict( "Text" => String,        
                           "Code" => String,                                                
                           "Name" => String,        
                           "Tag"  => String,         
                           "Uri"  => String,         
                           "Date" => String,  #change later        
                           "DateTime" => String,     
                           "Version" => String,     
                           "Dimension" => Number,   
                           "Range"  => Range,       
                           "Count"  => Number,     
                           "Index"  => Number,       
                           "Integer" => Number,     
                           "Real" =>    Number,        
                           "Imag" =>    Number,  #really?        
                           "Complex" => Complex,     
                           # Symop       
                           # Implied     
                           # ByReference
                           "Array" => Array,
                           "Matrix" => Matrix,
                           "List" => Array{Any}
                           )


"""Get the julia type for a given category and object"""
get_julia_type(cifdic,cat,obj) = begin
    definition = get_by_cat_obj(cifdic,(cat,obj))
    base_type = definition["_type.contents"]
    cont_type = get(definition,"_type.container","Single")
    julia_base_type = get(type_mapping,base_type,Any)
    final_type = julia_base_type
    if cont_type != "Single"
        final_type = :($(type_mapping[cont_type]){$julia_base_type})
    return final_type
end

"""For simplicity, the Python-Lark transformer does not annotate
any types except for the function return type. The following routine
traverses an expression, and inserts the appropriate types"""

"""Any category assignments are done using a separate
equals statement, so we record those as they happen. An AST
node is a two-element structure, where the first element is
the type and the second element is an array of arguments.

The following code updates a dictionary of assignments,
and in parallel appends type information when a getindex
call corresponds to a known category/object combination.""".

# Keep a track of assignments, and assign types
# Each case has implications for the assignment dictionary
# and for the filtered AST.

ast_assign_types(ast_node,in_scope_dict,lhs=nothing,cifdic=Dict()) = begin
    println("$ast_node: in scope $in_scope_dict")
    ixpr = :(:call,:f)  #dummy
    if typeof(ast_node) == Expr && ast_node.head == :(=)
        # we only care if the final type is tagged as a categoryobject
        println("Found assignment for $ast_node")
        lh = ast_node.args[1]
        # this is for the filtering
        ixpr.head = ast_node.head
        ixpr.args = [ast_assign_types(x,in_scope_dict,lh,cifdic) for x in ast_node.args]
        return ixpr
    elseif typeof(ast_node) == Expr && lhs != nothing && ast_node.head == :(::)
        if ast_node.args[2] == :CategoryObject
            in_scope_dict[lhs] = ast_node.args[1]
        end
        ixpr.head = ast_node.head
        ixpr.args = ast_node.args
        return ixpr
    elseif typeof(ast_node) == Expr && ast_node.head in [:block,:for]
        new_scope_dict = deepcopy(in_scope_dict)
        println("New scope!")
        ixpr.head = ast_node.head
        ixpr.args = [ast_assign_types(x,new_scope_dict,nothing,cifdic) for x in ast_node.args]
        println("At end of scope: $new_scope_dict")
        return ixpr
    elseif typeof(ast_node) == Expr && ast_node.head == :call && ast_node.args[1] == :getindex
        println("Found call of getindex")
        if ast_node.args[2] in keys(in_scope_dict)
            cat,obj = in_scope_dict[ast_node.args[2]],ast_node.args[3]
            final_type = get_julia_type(cifdic,cat,obj)
            println("category $cat object $obj type $final_type")
            return :($ast_node::$final_type)
        else
            ixpr.head = ast_node.head
            ixpr.args = [ast_assign_types(x,in_scope_dict,nothing,cifdic) for x in ast_node.args]
            return ixpr
        end
    elseif typeof(ast_node) == Expr
        ixpr.head = ast_node.head
        ixpr.args = [ast_assign_types(x,in_scope_dict,nothing,cifdic) for x in ast_node.args]
        return ixpr
    else
        return ast_node
    end
end
        
#== The Tables.jl interface functions
==#

Tables.istable(::Type{<:CategoryObject}) = true

Tables.rows(c::CategoryObject) = c

Tables.rowaccess(::Type{<:CategoryObject}) = true

Tables.schema(c::CategoryObject) = nothing


