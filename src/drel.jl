#== Definitions for running dREL code in Julia
==#

export CategoryObject

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

#==
For simplicity, the Python-Lark transformer does not annotate
any types except for the function return type. The following routine
traverses an expression, and inserts the appropriate types

Any category assignments are done using a separate
equals statement, so we record those as they happen. An AST
node is a two-element structure, where the first element is
the type and the second element is an array of arguments.

The following code updates a dictionary of assignments,
and in parallel appends type information when a getindex
call corresponds to a known category/object combination.
==#
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

