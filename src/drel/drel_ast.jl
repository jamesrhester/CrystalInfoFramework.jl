
export ast_fix_indexing,fix_scope,find_target, cat_to_packet

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

ast_assign_types(ast_node,in_scope_dict;lhs=nothing,cifdic=Dict()) = begin
    println("$ast_node: in scope $in_scope_dict")
    ixpr = :(:call,:f)  #dummy
    if typeof(ast_node) == Expr && ast_node.head == :(=)
        # we only care if the final type is tagged as a categoryobject
        println("Found assignment for $ast_node")
        lh = ast_node.args[1]
        # this is for the filtering
        ixpr.head = ast_node.head
        ixpr.args = [ast_assign_types(x,in_scope_dict,lhs=lh,cifdic=cifdic) for x in ast_node.args]
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
        ixpr.args = [ast_assign_types(x,new_scope_dict,lhs=nothing,cifdic=cifdic) for x in ast_node.args]
        println("At end of scope: $new_scope_dict")
        return ixpr
    elseif typeof(ast_node) == Expr && ast_node.head == :call && ast_node.args[1] == :getindex
        println("Found call of getindex")
        if ast_node.args[2] in keys(in_scope_dict)
            cat,obj = in_scope_dict[ast_node.args[2]],ast_node.args[3]
            final_type,final_cont = get_julia_type_name(cifdic,cat,obj)
            println("category $cat object $obj type $final_type")
            return :($ast_node::$final_type)
        else  #normal indexing
            ixpr.head = ast_node.head
            ixpr.args = [ast_assign_types(x,in_scope_dict,lhs=nothing,cifdic=cifdic) for x in ast_node.args]
            ixpr.args[3] = :($(ixpr.args[3])+1)
            return ixpr
        end
    elseif typeof(ast_node) == Expr && ast_node.head == :ref
        println("Found subscription")
        if ast_node.args[1] in keys(in_scope_dict)
            cat,obj = in_scope_dict[ast_node.args[1]],ast_node.args[2]
            final_type,final_cont = get_julia_type_name(cifdic,cat,obj)
            println("Category $cat object $obj type $final_type")
            return :($ast_node::$final_type)
        else    #normal indexing
            ixpr.head = ast_node.head
            ixpr.args = [ast_assign_types(x,in_scope_dict,lhs=nothing,cifdic=cifdic) for x in ast_node.args]
            ixpr.args[2] = :($(ixpr.args[2])+1)
            return ixpr
        end
    elseif typeof(ast_node) == Expr
        ixpr.head = ast_node.head
        ixpr.args = [ast_assign_types(x,in_scope_dict,lhs=nothing,cifdic=cifdic) for x in ast_node.args]
        return ixpr
    else
        return ast_node
    end
end

#== dREL uses 0-based indexing, but Julia uses 1-based indexing. We trawl through
the AST to find any index-type expressions, discarding anything that is, in fact
a category[object] reference. While this macro is similar to the one that assigns
types, we keep it separate for maintainability.  ``In_scope_list`` should contain
a list of variable names that are in scope as category names or packets. We do
not touch slices, as are assumed to have been caught earlier. ==#

ast_fix_indexing(ast_node,in_scope_list;lhs=nothing) = begin
    #println("$ast_node: in scope $in_scope_list")
    ixpr = :(:call,:f)  #dummy
    if typeof(ast_node) == Expr && ast_node.head == :(=)
        # we only care if the final type is tagged as a categoryobject or is in scope
        println("Found assignment for $ast_node")
        lh = ast_node.args[1]
        # this is for the filtering
        ixpr.head = ast_node.head
        ixpr.args = [ast_fix_indexing(x,in_scope_list,lhs=lh) for x in ast_node.args]
        if ixpr.args[2] == Symbol("__packet")
            push!(in_scope_list,lh)
        end
        return ixpr
    elseif typeof(ast_node) == Expr && lhs != nothing && ast_node.head == :(::)
        if ast_node.args[2] == :CategoryObject
            push!(in_scope_list, lhs)
        end
        ixpr.head = ast_node.head
        ixpr.args = ast_node.args
        return ixpr
    elseif typeof(ast_node) == Expr && ast_node.head in [:block,:for]
        new_scope_list = deepcopy(in_scope_list)
        println("New scope!")
        ixpr.head = ast_node.head
        ixpr.args = [ast_fix_indexing(x,new_scope_list,lhs=nothing) for x in ast_node.args]
        println("At end of scope: $new_scope_list")
        return ixpr
    elseif typeof(ast_node) == Expr && ast_node.head == :call && ast_node.args[1] == :getindex
        println("Found call of getindex")
        ixpr.head = ast_node.head
        ixpr.args = [ast_fix_indexing(x,in_scope_list,lhs=nothing) for x in ast_node.args]
        if !(ast_node.args[2] in in_scope_list)
            ixpr.args[3] = :($(ixpr.args[3])+1)
        end
        return ixpr
    elseif typeof(ast_node) == Expr && ast_node.head == :ref
        println("Found subscription")
        ixpr.head = ast_node.head
        ixpr.args = [ast_fix_indexing(x,in_scope_list,lhs=nothing) for x in ast_node.args]
        if !(ast_node.args[1] in in_scope_list)
            println("Checking node $(ixpr.args[2])")
            if typeof(ixpr.args[2]) ==  Expr && ixpr.args[2].head == :call && ixpr.args[2].args[1] == :(:)
                ixpr.args[2].args[2] = :($(ixpr.args[2].args[2])+1)
                # no need to adjust endpoint as Julia is inclusive, dREL is exclusive
            else  # multi-indexing, has anything been missed?
                for i in 2:length(ixpr.args)
                    ixpr.args[i] = :($(ixpr.args[i])+1)
                end
            end
        end
        return ixpr
    elseif typeof(ast_node) == Expr
        ixpr.head = ast_node.head
        ixpr.args = [ast_fix_indexing(x,in_scope_list,lhs=nothing) for x in ast_node.args]
        return ixpr
    else
        return ast_node
    end
end

#== A function to detect instances of the target dataname

Unfortunately the Lark parser only determines category aliases
after the body has been processed, so it is impossible to
substitute in the return variable. So we do that in this function.
Furthermore, where the target is directly assigned to a 
square-bracketed expression, that expression is coerced to a
Matrix if the dictionary type is Matrix or Array.
==#

find_target(ast_node,alias_name,target_obj;is_matrix=false) = begin
    ixpr = :(:call,:f)  #dummy
    if typeof(ast_node) == Expr && ast_node.head == :(=)
        ixpr.head = ast_node.head
        ixpr.args[1] = find_target(ast_node.args[1],alias_name,target_obj)
        if ixpr.args[1] == :__dreltarget && is_matrix
            if typeof(ast_node.args[2]) == Expr && ast_node.args[2].head == :vect
                println("Fixing implicit matrix assignment")
                ixpr.args[2] = :(to_julia_array($(ast_node.args[2])))
            else
                ixpr.args[2] = ast_node.args[2]
            end
        else
            ixpr.args[2] = ast_node.args[2]  #no target on RHS
        end
        return ixpr
    elseif typeof(ast_node) == Expr && ast_node.head == :ref
        if ast_node.args[1] == Symbol(alias_name)
            if ast_node.args[2] == :(Symbol(lowercase($target_obj)))
                return :__dreltarget
            else
                return ast_node
            end
        else
            return ast_node
        end
    elseif typeof(ast_node) == Expr
        ixpr.head = ast_node.head
        ixpr.args = [find_target(x,alias_name,target_obj,is_matrix=is_matrix) for x in ast_node.args]
        return ixpr
    else
        return ast_node
    end
end

#== A function to detect assignments inside code blocks. As dREL
follows Python behaviour and considers that variables in do loops
exist beyond the end of the do loop, and that subsequent iterations
refer to the same variables assigned in previous iterations, we must
lift all variable assignments to the outer level.  We find all
assignments and assign to 'missing' at the top of the provided
block. Note that this assumes code from dREL in that we can assume no
global variables and no assignments to dictionary datanames (because
that is forbidden), and no use of the "local" keyword as we do not do
that when generating Julia code. 

The ast node passed to the routine should begin with a function
definition ==#

fix_scope(ast_node) = begin
    if !(ast_node.head == :(=) && ast_node.args[1].head == :call && ast_node.args[2].head == :block) 
        return ast_node
    end
    enclosing = :()
    enclosing.head = ast_node.head
    enclosing.args = []
    push!(enclosing.args,ast_node.args[1])
    all_assignments = unique(collect_assignments(ast_node.args[2]))
    ixpr = :(begin end)
    for s in all_assignments
        push!(ixpr.args,:($s = missing))
    end
    for a in ast_node.args[2].args
        push!(ixpr.args,a)
    end
    push!(enclosing.args,ixpr)
    return enclosing
end

collect_assignments(ast_node) = begin
    assigns = []
    if typeof(ast_node) == Expr && ast_node.head == :(=)   #assignment
        # Store new local variable if not already defined
        # Don't care about double assignment
        if typeof(ast_node.args[1]) == Symbol
            push!(assigns,ast_node.args[1])
        end
    elseif typeof(ast_node) == Expr
        for i in 1:length(ast_node.args)
            append!(assigns,collect_assignments(ast_node.args[i]))
        end
    end
    return assigns
end

#==
Set category packets can be referenced directly without any looping
statement. Our transformer creates a category object for every category
mentioned, but does not know about Set categories. We do, and so we
catch the CategoryObject creation and create a CatPacket.

NB: nested CategoryObject calls will fail. Should not exist. ==#

cat_to_packet(ast_node,set_cats) = begin
    ixpr = :()
    if typeof(ast_node) == Expr && ast_node.head == :call
        ixpr.head = ast_node.head
        if ast_node.args[1] == :CategoryObject && ast_node.args[3] in set_cats
            ixpr = :(first_packet($ast_node))
        else
            ixpr.args = [cat_to_packet(x,set_cats) for x in ast_node.args]
        end
    elseif typeof(ast_node) == Expr
        ixpr.head = ast_node.head
        ixpr.args = [cat_to_packet(x,set_cats) for x in ast_node.args]
    else
        return ast_node
    end
    return ixpr
end

#== Convert the dREL array representation to the Julia representation...
recursively. A dREL array is a sequence of potentially nested lists. Each
element is separated by a comma. This becomes, in Julia, a vector of
vectors, which is ultimately one-dimensional. So we loop over each element,
stacking each vector at each level into a 2-D array. Note that, while we
swap the row and column directions (dimensions 1 and 2) the rest are 
unchanged. Each invocation of this routine returns the actual level
that is currently being treated, together with the result of working
with the previous level.

Vectors in dREL are a bit magic, in that they conform themselves
to be row or column as required. We have implemented this in
the runtime, so we need to turn any single-dimensional array
into a drelvector ==#

to_julia_array(drel_array) = begin
    if ndims(drel_array) == 1 && eltype(drel_array) <: Number
        return drelvector(drel_array)
    else
        return to_julia_array_rec(drel_array)[2]
    end
end

to_julia_array_rec(drel_array) = begin
    if eltype(drel_array) <: AbstractArray   #can go deeper
        sep_arrays  = to_julia_array_rec.(drel_array)
        level = sep_arrays[1][1]  #level same everywhere
        result = (x->x[2]).(sep_arrays)
        if level == 2
            println("$level:$result")
            return 3, vcat(result...)
        else
            println("$level:$result")
            return level+1, cat(result...,dims=level)
        end
    else    #primitive elements, make them floats
        println("Bottom level: $drel_array")
        return 2,hcat(Float64.(drel_array)...)
    end
end
