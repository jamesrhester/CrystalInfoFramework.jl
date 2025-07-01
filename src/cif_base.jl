#
# *Basic operations on CIF*
#

#  **CIF values**
#
# CIF1 allows only string/missing/null values, whereas CIF2 introduces both
# "tables" and lists.

# **CIF containers**
#
# CIF containers hold collections of CIF values, indexed by strings.

"""
A `CifContainer` holds a series of one-dimensional arrays indexed by strings, and the name of a
source of the data. Arrays are organised into groups, called "loops". Subtypes should
implement `get_source_file` and `get_data_values`.
"""
abstract type CifContainer <: AbstractDict{String, Any} end

"""
    get_source_file(c::CifContainer)

The (possibly empty) name of the source for the data in the container.
"""
function get_source_file end

"""
    get_data_values(c::CifContainer)

A `Dict{String,V}` of 1D array-valued items.
"""
function get_data_values end

"""
    get_loop_names(b::CifContainer)

Return all looped data names as an array of arrays, where names are grouped by the loop
in which they occur.
"""
function get_loop_names end

"""
    get_loop(b::CifContainer,s)

A `DataFrame` built from data items in the same loop as `s`. If no data are available,
an empty `DataFrame` is returned.
"""
get_loop(b::CifContainer,s) = begin
    loop_names = [l for l in get_loop_names(b) if s in l]
    # Construct a DataFrame
    df = DataFrame()
    if length(loop_names) == 1
        for n in loop_names[1]
            df[!,Symbol(n)]=get_data_values(b)[n]
        end
    elseif length(loop_names) > 1
        error("More than one loop contains data name $s")
    end
    return df
end

"""
    get_loop_names(b::CifContainer,n::AbstractString)

Return all names in the loop that also contains `n`.
"""
get_loop_names(b::CifContainer,n::AbstractString) = begin

    loop_names = [l for l in get_loop_names(b) if n in l]

    if length(loop_names) > 1
        error("More than one loop contains data name $n")
    elseif length(loop_names) == 0
        return []
    end

    loop_names[]
end

length(c::CifContainer) = length(keys(c))

"""
    keys(b::CifContainer)

All data names in `b`
"""
keys(b::CifContainer) = keys(get_data_values(b))

"""
    haskey(b::CifContainer,s::String)

Returns `true` if `b` contains a value for case-insensitive data name `s`
"""
haskey(b::CifContainer, s::String) = haskey(get_data_values(b),lowercase(s))

"""
    iterate(b::CifContainer)
    
Iterate over all data names in `b`.
"""
iterate(b::CifContainer) = iterate(get_data_values(b))
iterate(b::CifContainer,s) = iterate(get_data_values(b),s)

"""
    getindex(b::CifContainer,s::String)

`b[s]` returns all values for case-insensitive data name `s` in 
`b` as an `Array`
"""
getindex(b::CifContainer,s::String) = get_data_values(b)[lowercase(s)]

"""
    get(b::CifContainer,s::String,a)

Return `b[s]`. If `s` is missing, return `a`. `s` is case-insensitive.
"""
get(b::CifContainer,s::String,a) = get(get_data_values(b),lowercase(s),a)

"""
    getindex(b::CifContainer,s::Dict)

Return the set of values in `b` corresponding to the data name values
provided in `s`. The keys of `s` must be datanames found in `b`. A
DataFrame is returned. The keys of `s` are case-insensitive.  
"""
getindex(b::CifContainer,s::Dict) = begin
    l = get_loop(b,first(s).first)
    for (k,v) in s
        l = l[l[!,Symbol(lowercase(k))] .== v, :]
    end
    l
end

"""
    setindex!(b::CifContainer,v,s)

Set the value of `s` in `b` to `v`
"""
setindex!(b::CifContainer,v,s) = begin
    get_data_values(b)[lowercase(s)]=v
end

"""
    delete!(b::CifContainer,s)

Remove the value of `s` from `b`
"""
delete!(b::CifContainer,s) = begin
    delete!(get_data_values(b),lowercase(s))

    # Remove loop information
    old_loop_info = get_loop_names(b, s)
    if old_loop_info != []
        # Remove old loop
        set_loop_names(b, filter( x-> !(lowercase(s) in x), get_loop_names(b)))
        new_loop_names = filter( x -> x != lowercase(s), old_loop_info)
        if length(new_loop_names) > 0
            create_loop!(b, new_loop_names)
        end
    end
    
end

"""
    rename!(b::CifContainer, old, new)

Change dataname `old` to `new`, retaining values and loop structure.
"""
rename!(b::CifContainer, old, new) = begin
    old = lowercase(old)
    new = lowercase(new)
    if old == new return end
    old_loop_info = get_loop_names(b, old)

    # Remove old loop
    set_loop_names(b, filter( x -> x != old_loop_info, get_loop_names(b)))
    b[new] = b[old]
    delete!(b, old)

    # Add new loop
    new_pos = indexin([old], old_loop_info)[]
    if !isnothing(new_pos)
        old_loop_info[new_pos] = new
        create_loop!(b, old_loop_info)
    end
    
end

# ***Nested CIF containers***

# A container with nested blocks (save frames). These are returned by the
# method `get_frames`. In all other ways a nested cif container behaves
# as if the save frames are absent.

"""
A CIF container with nested blocks (save frames). Data names in the
nested block are hidden.
"""
abstract type NestedCifContainer <: CifContainer end

"""
    get_frames(c::NestedCifContainer)

Return all nested containers in `c`. 
"""
function get_frames end

# Two types of concrete `CifContainer`s are available: `Block`,
# which is not nested, and `CifBlock` which may contain nested
# containers. Loops are represented as lists of the datanames that are
# in the same loop. All data values are stored separately as lists
# indexed by dataname.

"""
A CIF data block or save frame containing no nested save frames.
"""
mutable struct Block <: CifContainer
    loop_names::Vector{Vector{String}} #one loop is a list of datanames
    data_values::Dict{String,Vector}
    original_file::AbstractString
end

Block() = begin
    Block(Vector{String}[],Dict{String,Vector{String}}(),"")
end

"""
A CIF block potentially containing save frames. Save frames cannot be nested.
"""
mutable struct CifBlock <: NestedCifContainer
    save_frames::Dict{String,Block}
    loop_names::Vector{Vector{String}} #one loop is a list of datanames
    data_values::Dict{String,Vector}
    original_file::AbstractString
end

Block(f::CifBlock) = Block(get_loop_names(f),get_data_values(f),get_source_file(f))
CifBlock(n::Block) = CifBlock(Dict{String,Block}(),get_loop_names(n),get_data_values(n),n.original_file)
CifBlock(f::CifBlock) = f
CifBlock() = CifBlock(Block())

# And a simple access API
get_data_values(b::Block) = b.data_values
get_data_values(b::CifBlock) = b.data_values
set_data_values(b::Block,v) = begin b.data_values = v end
set_data_values(b::CifBlock,v) = begin b.data_values = v end

get_loop_names(b::Block) = b.loop_names
get_loop_names(b::CifBlock) = b.loop_names
set_loop_names(b::Block,n) = begin b.loop_names = n end
set_loop_names(b::CifBlock,n) = begin b.loop_names = n end

get_source_file(b::Block) = b.original_file
get_source_file(f::CifBlock) = f.original_file

# **Collections of CIF containers**
#
# A CIF file is a `CifCollection`. Indexing produces a
# `CifContainer`.  There are no CIF Values held at the top level.

"""
A collection of CIF containers indexed by strings
"""
abstract type CifCollection <: AbstractDict{String, CifContainer} end

# When displaying a `CifCollection` a save frame is generated

Base.show(io::IO,::MIME"text/plain",c::CifCollection) = begin
    for k in keys(c)
        write(io,"save_$k\n")
        show(io,c[k])
    end
end

# Show displays a quasi-CIF for informational purposes

Base.show(io::IO,::MIME"text/plain",c::CifContainer) = begin
    write(io,"\n")
    key_vals = setdiff(collect(keys(c)),get_loop_names(c))
    for k in key_vals
        item = format_for_cif(first(c[k]))
        write(io,"$k\t$item\n")
    end
    
    # now go through the loops
    for one_loop in get_loop_names(c)
        a_loop = get_loop(c,first(one_loop))
        write(io,format_for_cif(a_loop))
    end
end

Base.show(io::IO,::MIME"text/plain",b::NestedCifContainer) = begin
    # first output the save frames
    show(io,get_frames(b))
    show(io,Block(b))
end

"""
    add_to_loop!(b::CifContainer, tgt, newname)

Add dataname `newname` to the loop containing `tgt`. Values for `newname` must already
be present (e.g. by calling `b[newname]=values`) and have the same length as other 
values in the loop.
"""
add_to_loop!(b::CifContainer, tgt, newname) = begin
    loop_id = filter(l -> tgt in l, get_loop_names(b))
    if length(loop_id) != 1
        throw(error("No single unique loop containing dataname $tgt"))
    end
    # remove new name from any other loops
    set_loop_names(b, map(x -> filter!(y -> !(y == newname),x), get_loop_names(b)))
    # and drop any that are now empty
    set_loop_names(b,filter(x -> !isempty(x),get_loop_names(b)))
    if length(b[tgt]) != length(b[newname])
        throw(error("Mismatch in lengths: $(length(b[tgt])) and $(length(b[newname]))"))
    end
    push!(loop_id[1],newname)
end

"""
    create_loop!(b::CifContainer,names)

Create a loop in `b` from the datanames in `names`.  Datanames 
previously assigned to
other loops are transferred to the new loop. All data attached to `names` 
should have the same length.
"""
create_loop!(b::CifContainer, names) = begin
    l = unique(length.([b[n] for n in names]))
    if length(l) > 1
        throw(error("Attempt to create loop with mismatching data name lengths: $l"))
    end
    # drop names from other loops
    set_loop_names(b, map(x -> filter!(y -> !(y in names),x), get_loop_names(b)))
    # drop empty loops
    set_loop_names(b,filter!(x->!isempty(x),get_loop_names(b)))
    push!(get_loop_names(b),names)
end

"""
    drop_row!(b::CifContainer, name, loc)

Drop the row with index `loc` from the loop containing `name` in
`b`. This is an internal routine and is not part
of the public API, as officially loops have no defined order.
"""
drop_row!(b::CifContainer, name, loc) = begin

    all_names = [l for l in get_loop_names(b) if name in l]
    if length(all_names) != 1
        throw(error("No unique loop found for $name"))
    end

    all_names = all_names[]
    if length(b[all_names[1]]) == 1
        if loc == 1
            for a in all_names
                delete!(b,a)
            end
        else
            throw(error("Request to drop row > 1 for one-row loop"))
        end
    elseif length(b[all_names[1]]) >= loc
        for a in all_names
            b[a] = vcat(b[a][1:loc-1], b[a][loc+1:end])
        end
        @debug "Dropped row $loc from loop containing $name"
    else
        @error "Request to drop beyond end of loop" loc length(b[all_names[1]]) name
        throw(error("Request to drop row $loc > length of loop containing $name"))
    end
            
end

# **CIF files**
# 
# A CIF file is represented as a collection of CIF blocks, and retains
# memory of the source file. Each of the component blocks is indexed by a string.
#
"""
A CIF file consisting of a collection of `CifContainer` indexed by String and
recording the source of the collection.
"""
struct Cif{T <: CifContainer} <: CifCollection
    contents::Dict{String,T}
    original_file::AbstractString
    header_comments::String
end

Cif{T}() where T = begin
    return Cif(Dict{String,T}(), "", "")
end

Cif() = Cif{ CifBlock }()

"""
    keys(c::Cif)

The names of all blocks in `c`, not including any save frames.
"""
keys(n::Cif) = keys(n.contents)

"""
    first(c::Cif)

The first block in `c`, which may not be the first block that
appears in the physical file.  This is useful when only one
block is present.
"""
first(n::Cif) = first(n.contents)

"""
    length(c::Cif)

The number of blocks in `n`.
"""
length(n::Cif) = length(n.contents)

"""
    haskey(c::Cif,name)

Whether `c` has a block named `name`.
"""
haskey(n::Cif,s) = begin
    if haskey(n.contents,s) return true end
    return lowercase(s) in lowercase.(keys(n.contents))
end

"""
    getindex(c::Cif,n)

`c[n]` returns the block case-insensitively named `n` in `c`.
"""
getindex(n::Cif,s) = begin
    try
        return n.contents[s]     # optimisation for matching case
    catch e
        if e isa KeyError
            sl = lowercase(s)
            real_key = filter(x->lowercase(x)==sl,keys(n.contents))
            if length(real_key)!=1 rethrow() end
            n.contents[first(real_key)]
        else rethrow()
        end
    end
end

"""
    setindex!(c::Cif,v,n)

`c[n] = s` sets block `n` to `v` in `c`.
"""
setindex!(c::Cif,v,s) = begin
    c.contents[s]=v
end

iterate(c::Cif) = iterate(c.contents)
iterate(c::Cif,s) = iterate(c.contents,s)
"""
    show(io::IO,::MIME"text/plain",c::Cif)

Display a text representation of `c` to `io`. This
text representation is not guaranteed to be syntactically
correct CIF. To display `c` as a CIF file, use
`::MIME"text/cif"`.
"""
show(io::IO,::MIME"text/plain",c::Cif) = begin
    write(io,c.header_comments)
    for k in keys(c)
        write(io,"data_$k\n")
        show(io,c[k])
    end
end

get_contents(n::Cif) = n.contents
get_source_file(n::Cif) = n.original_file
get_header_comments(n::Cif) = n.header_comments

# Obtaining save frames.

"""
    get_frames(f::CifBlock)

Return all nested CIF containers in `f` as a `Cif` object.
"""
get_frames(f::CifBlock) = Cif{Block}(f.save_frames,get_source_file(f),"")

"""
    Cif(somepath; version=0)

Read in filename `s` as a CIF file.  `version` may be `1`, `2` or
`0` (default) for auto-detected CIF version.

"""
Cif(somepath; version=0) = begin
    ## get the full filename and make sure we have a string.
    full = convert(String, realpath(somepath))
    pathstring = URI(full).path
    Cif(open(full), version = version, source = full)
end

Cif(io::IO; version = 0, source = nothing) = begin
    full_contents = read(io, String)
    if isnothing(source) source = "$io" end
    cif_from_string(full_contents, version = version, source = source)
end

"""
    cif_from_string(s::AbstractString; version=0, source="")

Process `s` as the text of a CIF file.
`version` may be `1`, `2` or `0` (default) for auto-detected CIF
version. If `source` is provided, it is a filesystem location to
record as the source for `s`.
"""
cif_from_string(s::AbstractString; version=0, source="") = begin
    if length(s) > 1 && s[1] == '\ufeff'
        s = s[(nextind(s,1)):end]
    end
    if version == 0
        actual_version = auto_version(s)
    else
        actual_version = version
    end
    ct = TreeToCif(source,get_header_comments(s))
    if actual_version == 2
        return Lerche.transform(ct,Lerche.parse(cif2_parser,s))
    else
        return Lerche.transform(ct,Lerche.parse(cif1_parser,s))
    end
end

"""
    auto_version(contents)

Determine the version of CIF adhered to by the string `contents`. If the string `#\\#CIF_2.0` is
not present, the version is assumed to be 1.1. 1.0 is not presently detected.
"""
auto_version(contents) = begin
    if length(contents) < 10 return 1.1 end
    if contents[1:10] == raw"#\#CIF_2.0" return 2 else return 1.1 end
end

"""
    get_header_comments(contents)

Extract any block of comments found before the first data block, without the comment
characters.
"""
get_header_comments(contents) = begin
    finder = r"^(#(.+)\n)+"
    x = match(finder,contents)
    if x === nothing return "" end
    no_comment = replace(x.match,r"^#"m => "")
    if length(no_comment) > 6 && no_comment[1:6] == "\\#CIF_"
        first_line_end = findfirst('\n',no_comment)
        no_comment = no_comment[first_line_end+1:end]
    end
    return no_comment
end
