#
# *Basic operations on CIF*
#

#  **CIF values**
#
# CIF1 allows only string/missing/null values, whereas CIF2 introduces both
# "tables" and lists.

"""
The syntactical type of data held in a CIF file. A value is of type `String`,
`Vector{CifValue}`, `Dict{String,CifValue}`, `Missing` or `Nothing`. In all
cases the values returned for a given data name are in an 
`Array{CifValue,1}`. 
"""
const CifValue = Union{String,Missing,Nothing,Vector{T},Dict{String,T}} where T
Base.nameof(CifValue) = Symbol("Cif Value")

# **CIF containers**
#
# CIF containers hold collections of CIF values, indexed by strings.

"""
A `CifContainer` holds a series of one-dimensional arrays indexed by strings, and the name of a
source of the data. Arrays are organised into groups, called "loops". Subtypes should
implement `get_source_file` and `get_data_values`.
"""
abstract type CifContainer{V} <: AbstractDict{String,V} end

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
haskey(b::CifContainer{V} where V,s::String) = haskey(get_data_values(b),lowercase(s))

"""
    iterate(b::CifContainer)
    
Iterate over all data names in `b`.
"""
iterate(b::CifContainer) = iterate(get_data_values(b))
iterate(b::CifContainer,s) = iterate(get_data_values(b),s)

"""
    getindex(b::CifContainer,s::String)

`b[s]` returns all values for case-insensitive data name `s` in 
`b` as an `Array{CifValue,1}`
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
end

# ***Nested CIF containers***

# A container with nested blocks (save frames). These are returned by the
# method `get_frames`. In all other ways a nested cif container behaves
# as if the save frames are absent.

"""
A CIF container with nested blocks (save frames). Data names in the
nested block are hidden.
"""
abstract type NestedCifContainer{V} <: CifContainer{V} end

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
mutable struct Block{V} <: CifContainer{V}
    loop_names::Vector{Vector{String}} #one loop is a list of datanames
    data_values::Dict{String,Vector{V}}
    original_file::String
end

Block{V}() where V = begin
    Block(Vector{String}[],Dict{String,Vector{V}}(),"")
end

"""
A CIF block potentially containing save frames. Save frames cannot be nested.
"""
mutable struct CifBlock{V} <: NestedCifContainer{V}
    save_frames::Dict{String,Block{V}}
    loop_names::Vector{Vector{String}} #one loop is a list of datanames
    data_values::Dict{String,Vector{V}}
    original_file::String
end

Block(f::CifBlock) = Block(get_loop_names(f),get_data_values(f),get_source_file(f))
CifBlock(n::Block{V}) where V = CifBlock(Dict{String,Block{V}}(),get_loop_names(n),get_data_values(n),n.original_file)
#CifBlock(f::CifBlock) = f

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
abstract type CifCollection{V} <: AbstractDict{String,V} end

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

Add dataname `tgt` to the loop containing newname. Values for `tgt` must already
be present (e.g. by calling `b[tgt]=values`) and have the same length as other 
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
    create_loop!(b::CifContainer,names::Array{String,1})

Create a loop in `b` from the datanames in `names`.  Datanames 
previously assigned to
other loops are transferred to the new loop. All data attached to `names` 
should have the same length.
"""
create_loop!(b::CifContainer,names::Array{String,1}) = begin
    l = unique(length.([b[n] for n in names]))
    if length(l) != 1
        throw(error("Attempt to create loop with mismatching data name lengths: $l"))
    end
    # drop names from other loops
    set_loop_names(b, map(x -> filter!(y -> !(y in names),x), get_loop_names(b)))
    # drop empty loops
    set_loop_names(b,filter!(x->!isempty(x),get_loop_names(b)))
    push!(get_loop_names(b),names)
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
struct Cif{V,T <: CifContainer{V}} <: CifCollection{V}
    contents::Dict{String,T}
    original_file::String
end

Cif{V,T}() where V where T = begin
    return Cif(Dict{String,T}(),"")
end

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
haskey(n::Cif,s) = haskey(n.contents,s)

"""
    getindex(c::Cif,n)

`c[n]` returns the block named `n` in `c`.
"""
getindex(n::Cif,s) = n.contents[s]

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
    for k in keys(c)
        write(io,"data_$k\n")
        show(io,c[k])
    end
end

get_contents(n::Cif) = n.contents
get_source_file(n::Cif) = n.original_file

# Obtaining save frames.

"""
    get_frames(f::CifBlock{V})

Return all nested CIF containers in `f` as a `Cif` object.
"""
get_frames(f::CifBlock{V}) where V = Cif{V,Block{V}}(f.save_frames,get_source_file(f))

# **Interface to low-level C API**

# We use the C libcifapi facility to stream values into Julia,
# building out our data structures in Julia, rather than using the
# higher-level cifapi routines that store values within the C side. In
# order to do this we have to maintain a context that is passed
# through the C library to the callback routines. We store the actual
# CIF collection that we are constructing, a list of blocks currently
# under construction, the source filename, and whether or not to print
# verbose information.

mutable struct cif_builder_context
    actual_cif::Dict{String,CifContainer{CifValue}}
    block_stack::Array{CifContainer{CifValue}}
    filename::String
    verbose::Bool
end

# libcifapi uses the `cif_parse_options` structure to manage parsing
# of the supplied CIF file. We set the appropriate values, in particular
# the `user_data` field will contain a `cif_builder_context` object above.

mutable struct cif_parse_options
    prefer_cif2::Int32
    default_encoding_name::Ptr{UInt8}
    force_default_encoding::Int32
    line_folding_modified::Int32
    text_prefixing_modifier::Int32
    max_frame_depth::Int32
    extra_ws_chars::Ptr{UInt8}
    extra_eol_chars::Ptr{UInt8}
    handler::Ref{cif_handler_tp}
    whitespace_callback::Ptr{Cvoid}
    keyword_callback::Ptr{Cvoid}
    dataname_callback::Ptr{Cvoid}
    error_callback::Ptr{Cvoid}
    user_data::cif_builder_context
end

# We have to pass a pointer to the cif_parse_options structure, not
# the structure itself, of course.

mutable struct cpo_ptr
    handle::Ptr{cif_parse_options}
end

# ***Cif walking functions***
#
# The following callback functions are passed to libcifapi to call
# when each parsing event is detected.

handle_cif_start(a,b)::Cint = begin
    #println("Cif started; nothing done")
    0
end

handle_cif_end(a,b)::Cint = begin
    #println("Cif is finished")
    0
end

# When a block is commenced, a new non-nested block is created
# and added on to the end of our current list of blocks.

handle_block_start(a::cif_container_tp_ptr,b)::Cint = begin
    blockname = get_block_code(a)
    if b.verbose
        println("New blockname $(blockname)")
    end
    newblock = Block{CifValue}()
    newblock.original_file = b.filename
    push!(b.block_stack,newblock)
    0
end

# When a block is finished, we remove all data names that have only
# `missing` values, then add it to the full CIF and remove it from
# our stack of blocks.

handle_block_end(a::cif_container_tp_ptr,b)::Cint = begin
    # Remove missing values
    all_names = keys(get_data_values(b.block_stack[end]))
    # Length > 1 dealt with already
    all_names = filter(x -> length(get_data_values(b.block_stack[end])[x]) == 1,all_names)
    # Remove any whose first and only entry is 'missing'
    drop_names = filter(x -> ismissing(get_data_values(b.block_stack[end])[x][1]),all_names)
    # println("Removing $drop_names from block")
    [delete!(b.block_stack[end],x) for x in drop_names]
    # and finish off
    blockname = get_block_code(a)
    if b.verbose println("Block is finished: $blockname") end
    b.actual_cif[blockname] = pop!(b.block_stack)
    0
end

# When a save frame is encountered the current block is converted into
# a `CifBlock` and the new block added on to the `block_stack`.

handle_frame_start(a::cif_container_tp_ptr,b)::Cint = begin
    blockname = get_block_code(a)
    if b.verbose
        println("Frame started: $blockname")
    end
    newblock = Block{CifValue}()
    newblock.original_file = b.filename
    b.block_stack[end] = CifBlock(b.block_stack[end])
    push!(b.block_stack,newblock)
    0
end

# At the end of a frame, we remove all `missing` values, then add the frame to the
# list of save frames of the next highest block on the stack

handle_frame_end(a,b)::Cint = begin
    # Remove missing values
    all_names = keys(get_data_values(b.block_stack[end]))
    # Length > 1 dealt with already
    all_names = filter(x -> length(get_data_values(b.block_stack[end])[x]) == 1,all_names)
    # Remove any whose first and only entry is 'missing'
    drop_names = filter(x -> ismissing(get_data_values(b.block_stack[end])[x][1]),all_names)
    [delete!(b.block_stack[end],x) for x in drop_names]
    final_frame = pop!(b.block_stack)
    blockname = get_block_code(a)
    b.block_stack[end].save_frames[blockname] = final_frame
    if b.verbose println("Frame $blockname is finished") end
    0
end

handle_loop_start(a,b)::Cint = begin
    #println("Loop started")
    0
end

# At the end of a loop we remove any datanames that are composed only of missing
# values. There is no need to do anything else as the values are already stored
# as vectors separately.

handle_loop_end(a::Ptr{cif_loop_tp},b)::Cint = begin
    if b.verbose
        println("Loop header $(keys(a))")
    end
    # ignore missing values
    loop_names = lowercase.(keys(a))
    not_missing = filter(x->any(y->!ismissing(y),get_data_values(b.block_stack[end])[x]),loop_names)
    create_loop!(b.block_stack[end],not_missing)
    # and remove the data
    missing_ones = setdiff(Set(loop_names),not_missing)
    #println("Removing $missing_ones from loop")
    [delete!(b.block_stack[end],x) for x in missing_ones]
    0
end

handle_packet_start(a,b)::Cint = begin
    #println("Packet started; nothing done")
    0
end

handle_packet_end(a,b)::Cint = begin
    #println("Packet is finished")
    0
end

# Values are read in and converted to the appropriate type, then
# appended to the list associated with the current dataname.

handle_item(a::Ptr{UInt16},b::cif_value_tp_ptr,c)::Cint = begin
    a_as_uchar = Uchar(a)
    val = ""
    keyname = make_jl_string(a_as_uchar)
    if c.verbose
        println("Processing name $keyname")
    end
    current_block = c.block_stack[end]
    syntax_type = get_syntactical_type(b)
    if syntax_type == cif_value_tp_ptr
        val = String(b)
    elseif syntax_type == cif_list
        val = cif_list(b)
    elseif syntax_type == cif_table
        val = cif_table(b)
    else val = syntax_type()
    end
    if c.verbose
        if !ismissing(val) && val != nothing
            println("With value $val")
        elseif ismissing(val)
            println("With value ?")
        else println("With value .")
        end
    end
    lc_keyname = lowercase(keyname)
    if !(lc_keyname in keys(get_data_values(current_block)))
        get_data_values(current_block)[lc_keyname]=[val]
    else
        push!(get_data_values(current_block)[lc_keyname],val)
    end
    return 0    
end

# This sets up the callbacks and configures the cifapi parser.

default_options(s::String;verbose=false) = begin
    handle_cif_start_c = @cfunction(handle_cif_start,Cint,(cif_tp_ptr,Ref{cif_builder_context}))
    handle_cif_end_c = @cfunction(handle_cif_end,Cint,(cif_tp_ptr,Ref{cif_builder_context}))
    handle_block_start_c = @cfunction(handle_block_start,Cint,(cif_container_tp_ptr,Ref{cif_builder_context}))
    handle_block_end_c = @cfunction(handle_block_end,Cint,(cif_container_tp_ptr,Ref{cif_builder_context}))
    handle_frame_start_c = @cfunction(handle_frame_start,Cint,(cif_container_tp_ptr,Ref{cif_builder_context}))
    handle_frame_end_c = @cfunction(handle_frame_end,Cint,(cif_container_tp_ptr,Ref{cif_builder_context}))
    handle_loop_start_c = @cfunction(handle_loop_start,Cint,(cif_loop_tp_ptr,Ref{cif_builder_context}))
    handle_loop_end_c = @cfunction(handle_loop_end,Cint,(Ptr{cif_loop_tp},Ref{cif_builder_context}))
    handle_packet_start_c = @cfunction(handle_packet_start,Cint,(Ptr{cif_packet_tp},Ref{cif_builder_context}))
    handle_packet_end_c = @cfunction(handle_packet_end,Cint,(Ptr{cif_packet_tp},Ref{cif_builder_context}))
    handle_item_c = @cfunction(handle_item,Cint,(Ptr{UInt16},cif_value_tp_ptr,Ref{cif_builder_context}))
    handlers = cif_handler_tp(handle_cif_start_c,
                              handle_cif_end_c,
                              handle_block_start_c,
                              handle_block_end_c,
                              handle_frame_start_c,
                              handle_frame_end_c,
                              handle_loop_start_c,
                              handle_loop_end_c,
                              handle_packet_start_c,
                              handle_packet_end_c,
                              handle_item_c,
                              )
    starting_cif = Dict()
    context = cif_builder_context(Dict(),CifContainer[],s,verbose)
    p_opts = cif_parse_options(0,C_NULL,0,1,1,1,C_NULL,C_NULL,Ref(handlers),C_NULL,C_NULL,C_NULL,C_NULL,context)
    return p_opts
end

"""
    Cif(s::AbstractString;verbose=false)

Read in filename `s` as a CIF file. If `verbose` is true, print
progress information during parsing. If `native` is `false`, use the
C-language parser provided by `libcif`.  If `libcif` is not available,
the native Julia parser will be used. `version` may be `1`, `2` or
`0` (default) for auto-detected CIF version.
`version` is only respected by the native parser. The `libcif` parser
will always auto-detect.  
"""
Cif(s::AbstractString;verbose=false,native=false,version=0) = begin
    ## get the full filename
    full = realpath(s)
    if find_library("libcif") != "" && !native
        p_opts = default_options(full,verbose=verbose)
        result = cif_tp_ptr(p_opts)
        ## the real result is in our user data context
        return Cif(p_opts.user_data.actual_cif,full)
    else
        if (!native) println("WARNING: using native parser as libcif not found on system.") end
        full_contents = read(full,String)
        # strip any BOM
        if length(full_contents) > 1 && full_contents[1] == '\ufeff'
            full_contents = full_contents[(nextind(full_contents,1)):end]
        end
        if version == 0
            actual_version = auto_version(full_contents)
        else
            actual_version = version
        end
        ct = TreeToCif(full)
        if actual_version == 2
            return Lerche.transform(ct,Lerche.parse(cif2_parser,full_contents))
        else
            return Lerche.transform(ct,Lerche.parse(cif1_parser,full_contents))
        end
    end
end

"""
    auto_version(contents)

Determine the version of CIF adhered to by the string `contents`. If the string `#\\#CIF_2.0` is
not present, the version is assumed to be 1.1. 1.0 is not presently detected.
"""
auto_version(contents) = begin
    if length(contents) < 10 return 1.1 end
    if contents[1:10] == r"#\#CIF_2.0" return 2 else return 1.1 end
end

# Given a filename, parse and return a CIF object according to the provided options.
# We access the underlying file pointer in order to pass it to the C library, and
# make sure to destroy the memory held by the C library afterwards.

cif_tp_ptr(p_opts::cif_parse_options)=begin
    ## obtain an IOStream
    filename = p_opts.user_data.filename
    f = open(filename,"r")
    fptr = Base.Libc.FILE(f)
    dpp = cif_tp_ptr(0)   #value replaced by C library
    ## Debugging: do we have good values in our parse options context?
    ## println("User context is $(p_opts.user_data)")
    val=ccall((:cif_parse,"libcif"),Cint,(FILE,Ref{cif_parse_options},Ref{cif_tp_ptr}),fptr,p_opts,dpp)
    close(fptr)
    close(f)
    finalizer(cif_destroy!,dpp)
    ## Check for errors and destroy the CIF if necessary
    if val != 0
        finalize(dpp)
        throw(error("File $filename load error: "* error_codes[val]))
    end
    ##q = time_ns()
    ##println("$q: Created cif ptr:$dpp for file $s")
    return dpp
end

