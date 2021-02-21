# The Native CIF parser

using Serialization

#==

We use the Lerche EBNF parser-generator to create a parser from
an EBNF specification. This is then applied to any given input
file to create a parse tree, following which the tree can be
traversed by a 'Transformer' subtype to convert to our internal
representation of a CIF file.

==#

# The parser is prebuilt (see deps/build.jl) and deserialised here.
# If this fails, consider running 'build.jl' again

const cif1_parser, cif2_parser = Serialization.deserialize(joinpath(@__DIR__,"..","deps","cif_grammar_serialised.jli"))

#==
== Introduction ==

Each transformer is named after a node in the parse tree, and
takes the contents of the node as an argument.  The transformers in
this file transform the parse tree into a Cif.

The transformer methods will assume that any interior nodes have
already been processed.

==#

struct TreeToCif <: Transformer
    source_name::String
end

@inline_rule quoted_string(t::TreeToCif,st) = begin
    ss = String(st)
    strip_string(ss)
end

strip_string(ss::String) = begin
    if length(ss) < 6 return ss[2:end-1] end
    if ss[1:3] == "'''" || ss[1:3] == "\"\"\""
        return ss[4:end-4] end
    return ss[2:end-1]
end

# We may have a \r\n combo in here so we have to
# be a little careful. And the cr/lf at the end
# of the last line is part of the delimiter
@rule semi_string(t::TreeToCif,args) = begin
    all_chars = length(args[1])
    as_string = String(args[1])
    no_semi = if as_string[2] == ';'
        if all_chars > 2 as_string[3:end] else "" end
    else
        @assert as_string[3] == ';'
        if all_chars > 3 as_string[4:end] else "" end
    end
    if length(args) == 2 final = no_semi
    else
        final = no_semi*join(String.(args[2:end-1]))
    end
    # chop off the very last line terminator if present
    if length(final)>1 && final[end-1:end] == "\r\n"
        return final[1:end-2]
    else
        return final[1:end-1]
    end
end

@inline_rule table_entry(t::TreeToCif,key,value) = begin
    return strip_string(String(key))=>value
end

@rule table(t::TreeToCif,args) = begin
    if length(args) == 2 return Dict{String,Any}() end
    # println("Processing $(args[2:end-1])")
    return Dict(args[2:end-1])
end

@rule list(t::TreeToCif,args) = begin
    if length(args) == 2 return [] end
    return args[2:end-1]
end

@inline_rule bare(t::TreeToCif,arg) = begin
    if arg == "." return nothing end
    if arg == "?" return missing end
    # println("Bare value, returning $arg")
    return String(arg)
end

@inline_rule data_value(t::TreeToCif,arg) = arg

@rule loop(t::TreeToCif,args) = begin
    # count data names
    boundary = findfirst(x->!isa(x,Token),args)
    name_list = String.(args[2:boundary-1])
    value_list = args[boundary:end]
    nrows,m = divrem(length(value_list),length(name_list))
    if m!=0 throw(error("Number of values in loop containing $(name_list[1]) is not a multiple of number of looped names")) end
    new_vals = reshape(value_list,length(name_list),:)
    per_name = permutedims(new_vals,[2,1])
    Dict{String,Array{CifValue,1}}(zip(name_list,eachcol(per_name)))
end

@inline_rule scalar_item(t::TreeToCif,dataname,datavalue) = begin
    if !ismissing(datavalue)
        String(dataname) => CifValue[datavalue]
    end
end

@inline_rule data(t::TreeToCif,arg) = arg

@inline_rule block_content(t::TreeToCif,arg) = arg

@rule save_frame(t::TreeToCif,args) = begin
    loop_list = Vector{Vector{String}}()
    contents = Dict{String,Vector{CifValue}}()
    b = Block{CifValue}(loop_list,contents,t.source_name)
    for l in args[2:end-1]
        # println("Adding $l")
        add_to_block(l,b)
    end
    name = String(args[1][6:end])
    name=>b
end

@rule dblock(t::TreeToCif,args) = begin
    save_frames = Dict{String,Block{CifValue}}()
    loop_names = Vector{Vector{String}}()
    data_values = Dict{String,Vector{CifValue}}()
    name = String(args[1])[6:end]
    cb = CifBlock(save_frames,loop_names,data_values,t.source_name)
    for data_item in args[2:end]
        add_to_block(data_item,cb)
    end
    name=>cb
end

add_to_block(data_item::Pair{String,T} where T<:CifContainer{CifValue},cb) = begin
    k,v = data_item
    if !haskey(cb.save_frames,k)
        cb.save_frames[k] = v
    else
        throw(error("Duplicate save frame name $k"))
    end
end

add_to_block(data_item::Pair{String,Array{CifValue,1}},cb) = begin
    k,v = data_item
    if !haskey(cb,k)
        cb[k] = v
    else
        throw(error("Duplicate item name $k"))
    end
end

add_to_block(data_item::Dict{String,Array{CifValue,1}},cb) = begin
    for nn in keys(data_item)
        if haskey(cb,nn) throw(error("Duplicate item name $nn")) end
    end
    non_missing = filter(x->any(y->!ismissing(y),data_item[x]),keys(data_item))
    for nn in non_missing
        cb[nn] = data_item[nn]
    end
    create_loop!(cb,collect(non_missing)) #collect as Array needed
end

add_to_block(::Nothing,cb) = cb

@rule input(t::TreeToCif,args) = begin
    Cif{CifValue,CifBlock{CifValue}}(Dict{String,CifBlock{CifValue}}(args),t.source_name)
end
