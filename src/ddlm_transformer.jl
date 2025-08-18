# Parsing DDLm dictionary directly

#==

We use the Lerche EBNF parser-generator to create a parser from
an EBNF specification. This is then applied to any given input
file to create a parse tree, following which the tree can be
traversed by a 'Transformer' subtype to convert to our internal
representation of a DDLm Dictionary.

Note that the constant cif2_parser is defined in cif2_transformer.jl
==#

#==
== Introduction ==

Each transformer is named after a node in the parse tree, and
takes the contents of the node as an argument.  The transformers in
this file transform the parse tree into a DDLm dictionary.

The transformer methods will assume that any interior nodes have
already been processed.

Our final goal is to create the datastructures of the
DDLm_Dictionary type.
==#

struct TreeToDDLm <: TreeToCif
    attr_dict::Dict{Symbol, Dict{Symbol, Vector}}
    source_name::AbstractString
    header_comments::AbstractString
end

@inline_rule scalar_item(t::TreeToDDLm, dataname, datavalue) = begin
    if any(x->isuppercase(x), dataname)
        dn = String(lowercase(dataname))
    else
        dn = String(dataname)
    end

    cat, obj = split(dn, ".")
    cat = Symbol(cat[2:end])
    obj = Symbol(obj)
    cat, Dict((obj => [datavalue]))
end

@rule loop(t::TreeToDDLm, args) = begin
    
    # count data names

    boundary = findfirst(x->!isa(x,Token),args)
    name_list = String.(args[2:boundary-1])

    nl = Vector{Symbol}(undef, length(name_list))
    cat = nothing
    for i in 1:length(name_list)
        if any(x->isuppercase(x), name_list[i])
            name_list[i] = lowercase(name_list[i])
        end
        c, o = split(name_list[i], '.')
        if isnothing(cat)
            cat = c[2:end]
        end

        if c[2:end] != cat
            throw(error("Loop contains items from more than one category: $c $cat"))
        end
        
        nl[i] = Symbol(o)
    end
    
    value_list = @view args[boundary:end]
    nrows,m = divrem(length(value_list),length(name_list))
    if m!=0 throw(error("Number of values in loop containing $(name_list[1]) is not a multiple of number of looped names")) end
    new_vals = reshape(value_list,length(name_list),:)
    per_name = permutedims(new_vals,[2,1])
    Symbol(cat), Dict{Symbol, Vector}(zip(nl,eachcol(per_name)))
end

#==

A save frame contains one definition. `args` will be a series of tuples (cat, Dict).

==#
@rule save_frame(t::TreeToDDLm, args) = begin

    name = String(args[1][6:end])
    defidx = findfirst( x -> x[1] == :definition && haskey(x[2], :id), args[2:end-1])

    if isnothing(defidx)
        defname = name
    else
        defname = lowercase(args[defidx+1][2][:id][])
    end

    # turn separated cat items into single dictionary entry

    marshall_args(t, args[2:end-1], defname)
    
    nothing  #all slurped up in t.attr_dict
end

#==

A datablock contains save frames and a dictionary-level information

==#
@rule dblock(t::TreeToCif, args) = begin

    name = String(args[1])[6:end]

    dicnameidx = findfirst( x -> x[1] == :dictionary && haskey(x[2], :title), args[2:end])

    @debug "Dic name at $dicnameidx" args[dicnameidx+1] length(args)
    
    dicname = lowercase(args[dicnameidx+1][2][:title][])
    marshall_args(t, args[2:end], dicname)
end

"""
    Put the (cat, dict) arguments into t.attr_dict
"""
marshall_args(t::TreeToDDLm, args, defname) = begin

    # For collecting single-value items

    cat_dicts = Dict{Symbol, Dict{Symbol, Vector}}()
    
    for l in args
        if isnothing(l) continue end
        cat, value_dict = l
        fk = first(keys(value_dict))
        if length(value_dict) > 1 || length(value_dict[fk]) > 1
            add_to_dict_block(t.attr_dict, l, defname)
        else
            new_val = value_dict[fk]
            if !haskey(cat_dicts, cat)
                cat_dicts[cat] = Dict{Symbol, Vector{Any}}()
            end
            cat_dicts[cat][fk] = new_val
        end
    end

    for cc in cat_dicts
        add_to_dict_block(t.attr_dict, cc, defname)
    end

end

add_to_dict_block(db::Dict{Symbol, Dict{Symbol, Vector}}, data_item, master_id) = begin

    cat, value_dict = data_item
    # @debug "Adding to block" cat value_dict master_id
    new_len = length(value_dict[first(keys(value_dict))])
    value_dict[:master_id] = fill(master_id, new_len)

    if !haskey(db, cat)
        db[cat] = Dict{Symbol, Vector}()
    end

    # Missing data names are filled in

    for obj in keys(db[cat])
        if !(haskey(value_dict, obj))
            value_dict[obj] = Vector{Any}(missing, new_len)
        end
    end

    # New data names are backfilled
    
    old_len = 0
    if !(isempty(db[cat]))
        old_len = length(db[cat][first(keys(db[cat]))])
    end
    
    for obj in keys(value_dict)
        if !(haskey(db[cat], obj))
            db[cat][obj] = Vector{Any}(missing, old_len)
        end
    end
    
    mergewith!(append!, db[cat], value_dict)     
end

@rule input(t::TreeToDDLm, args) = begin

    # Turn into a proper data frame

    df_attr_dict = Dict{Symbol, DataFrame}()
    for k in keys(t.attr_dict)
        df_attr_dict[k] = DataFrame(t.attr_dict[k])
    end

    nspace = get(t.attr_dict[:dictionary], :namespace, [""])[]
    return df_attr_dict, nspace
end
