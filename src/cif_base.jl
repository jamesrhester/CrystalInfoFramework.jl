
#== A CIF in Native Julia

The dREL approach requires multiple loops over data to be in process
simultaneously, which is not guaranteed to give coherent data for the
CIFAPI.  Therefore we use cif_walk to read in the data, using the cifapi
for parsing services only. We must define all handler functions in
this case.

Our Julia datastructure is built of a Dictionary of data blocks. A
data block is a List of Loops and a List of save frames, which are
themselves data blocks. A loop is a DataFrame. Single-valued items are
held in a loop with a single row.

==#

export NativeCif,NativeBlock
export get_save_frame, get_all_frames
export get_loop, eachrow, add_to_loop!, create_loop!,lookup_loop


"""The type of blocks and save frames"""

abstract type cif_container{V} <: AbstractDict{String,V} end

"""
The abstract cif type where the block elements all have primitive 
datatypes given by V
"""
abstract type Cif{V} <: AbstractDict{String,cif_container{V}} end

"""V, list(V) and table(string:V) all possible"""

get_dataname_type(c::cif_container{V} where V,d::AbstractString) = begin
    return Any
end

Base.length(c::cif_container) = length(keys(c))
Base.length(c::Cif{V} where V) = length(keys(c))
Base.iterate(c::Cif{V} where V) = iterate(get_contents(c))
Base.iterate(c::Cif{V} where V,i::Integer) = iterate(get_contents(c),i)

struct NativeCif <: Cif{cif_container{String}}
    contents::Dict{String,cif_container}
    original_file::String
end

get_contents(c::NativeCif) = c.contents

# Operations on Cifs
Base.getindex(c::NativeCif,s) = begin
    c.contents[s]
end

Base.setindex!(c::NativeCif,v,s) = begin
    c.contents[s]=v
end

Base.first(c::NativeCif) = first(c.contents)
Base.keys(c::NativeCif) = keys(c.contents)
Base.haskey(c::NativeCif,s::String) = haskey(c.contents,s)

mutable struct NativeBlock <: cif_container{Any}
    save_frames::Dict{String,cif_container{Any}}
    loop_names::Vector{Vector{String}} #one loop is a list of datanames
    data_values::Dict{String,Vector{Any}}
    original_file::String
end

NativeBlock() = begin
    NativeBlock(Dict(),[],Dict(),"")
end

Base.keys(b::NativeBlock) = keys(b.data_values)
Base.haskey(b::NativeBlock,s::String) = haskey(b.data_values,lowercase(s))
Base.iterate(b::NativeBlock) = iterate(b.data_values)
Base.iterate(b::NativeBlock,s) = iterate(b.data_values,s)
Base.length(b::NativeBlock) = length(b.data_values)
Base.getindex(b::NativeBlock,s::String) = b.data_values[lowercase(s)]
Base.get(b::NativeBlock,s::String,a) = get(b.data_values,lowercase(s),a)
get_datablock(b::NativeBlock) = b
                   
# We can specify a particular row in a loop by giving the
# values of the datanames.
Base.getindex(b::NativeBlock,s::Dict) = begin
    l = get_loop(b,first(s).first)
    for pr in s
        k,v = pr
        l = l[l[Symbol(k)] .== v, :]
    end
    if size(l,1) != 1
        println("WARNING: $s does not identify a unique row")
    end
    first(l)
end

Base.setindex!(b::NativeBlock,v,s) = begin
    b.data_values[lowercase(s)]=v
end

Base.delete!(b::NativeBlock,s) = begin
    delete!(b.data_values,lowercase(s))
end

"""
    get_loop(b,s) -> DataFrame

Return the contents of the loop containing data name s in block
b. If no data are available, a zero-length DataFrame is returned.
"""
get_loop(b::NativeBlock,s) = begin
    loop_names = [l for l in b.loop_names if s in l]
    # Construct a DataFrame
    df = DataFrame()
    if length(loop_names) == 1
        for n in loop_names[1]
            df[Symbol(n)]=b.data_values[n]
        end
    elseif length(loop_names) > 1
        error("More than one loop contains data name $s")
    end
    return df
end

"""

Convenience method: return the rows for which the requested data names
take the values provided in the dictionary.
"""
lookup_loop(b::NativeBlock,request::Dict{String,String}) = begin
    df = get_loop(b,first(request).first)
    for (k,v) in request
        df = df[df[Symbol(k)] .== v,:]
    end
    return df
end

"""
    add_to_loop!(b::NativeBlock, tgt, newname)

Add dataname `tgt` to the loop containing newname. Values for `tgt` must already
be present and have the same length as other values in the loop."""
add_to_loop!(b::NativeBlock, tgt, newname) = begin
    loop_id = filter(l -> tgt in l, b.loop_names)
    if length(loop_id) != 1
        throw(error("No single unique loop containing dataname $tgt"))
    end
    # remove new name from any other loops
    b.loop_names = map(x -> filter!(y -> !(y == newname),x), b.loop_names)
    # and drop any that are now empty
    filter!(x -> !isempty(x),b.loop_names)
    if length(b[tgt]) != length(b[newname])
        throw(error("Mismatch in lengths: $(length(b[tgt])) and $(length(b[newname]))"))
    end
    push!(loop_id[1],newname)
end

"""
    create_loop!(b::NativeBlock,names::Array{String,1})

Create a loop in ``b`` containing the datanames in ``names``.  Datanames assigned to
other loops are silently transferred to the new loop. All data attached to ``names`` 
should have the same length."""
create_loop!(b::NativeBlock,names::Array{String,1}) = begin
    l = unique(length.([b[n] for n in names]))
    if length(l) != 1
        throw(error("Attempt to create loop with mismatching data name lengths: $l"))
    end
    # drop names from other loops
    b.loop_names = map(x -> filter!(y -> !(y in names),x), b.loop_names)
    # drop empty loops
    filter!(x->!isempty(x),b.loop_names)
    push!(b.loop_names,names)
end

mutable struct cif_builder_context
    actual_cif::Dict{String,cif_container}
    block_stack::Array{cif_container}
    filename::String
    verbose::Bool
end

get_all_frames(c::NativeBlock) = begin
    NativeCif(c.save_frames,c.original_file)
end

get_save_frame(c::NativeBlock,s::String) = begin
    c.save_frames[s]
end

#== Merge the save frame lists of the second block files into the
first block. This routine is used in order to merge
dictionaries, for which the data block contents are less important ==#

merge_saves(combiner::Function,c::NativeBlock,d::NativeBlock) = begin
    merged_saves = merge(combiner,c.save_frames,d.save_frames)
    NativeBlock(merged_saves,c.loop_names,c.data_values,c.original_file)
end

"""An opaque type representing the parse options object in libcif"""
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

"""A pointer to a parse options structure"""
mutable struct cpo_ptr
    handle::Ptr{cif_parse_options}
end

"""Free C resources for parse options"""
pos_destroy!(x::cpo_ptr) = begin
    error_string = "Finalizing parse options $x"
    t = @task println(error_string)
    schedule(t)
    ccall((:free,"libc"),Cvoid,(Ptr{cif_parse_options},),x.handle)
end

#== Cif walking functions
==#

handle_cif_start(a,b)::Cint = begin
    #println("Cif started; nothing done")
    0
end

handle_cif_end(a,b)::Cint = begin
    #println("Cif is finished")
    0
end


handle_block_start(a::cif_container_tp_ptr,b)::Cint = begin
    blockname = get_block_code(a)
    if b.verbose
        println("New blockname $(blockname)")
    end
    newblock = NativeBlock(Dict(),Vector(),Dict(),b.filename)
    push!(b.block_stack,newblock)
    0
end


handle_block_end(a::cif_container_tp_ptr,b)::Cint = begin
    blockname = get_block_code(a)
    #println("Block is finished: $blockname")
    b.actual_cif[blockname] = pop!(b.block_stack)
    0
end


handle_frame_start(a::cif_container_tp_ptr,b)::Cint = begin
    blockname = get_block_code(a)
    if b.verbose
        println("Frame started: $blockname")
    end
    newblock = NativeBlock(Dict(),Vector(),Dict(),b.filename)
    push!(b.block_stack,newblock)
    0
end


handle_frame_end(a,b)::Cint = begin
    #println("Frame is finished")
    final_frame = pop!(b.block_stack)
    blockname = get_block_code(a)
    b.block_stack[end].save_frames[blockname] = final_frame 
    0
end


handle_loop_start(a,b)::Cint = begin
    #println("Loop started")
    0
end

handle_loop_end(a::Ptr{cif_loop_tp},b)::Cint = begin
    if b.verbose
        println("Loop header $(keys(a))")
    end
    create_loop!(b.block_stack[end],keys(a))
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
    if !(lc_keyname in keys(current_block.data_values))
        current_block.data_values[lc_keyname] = [val]
    else
        push!(current_block.data_values[lc_keyname],val)
    end
    return 0    
end

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
    context = cif_builder_context(Dict(),cif_container[],s,verbose)
    p_opts = cif_parse_options(0,C_NULL,0,0,0,1,C_NULL,C_NULL,Ref(handlers),C_NULL,C_NULL,C_NULL,C_NULL,context)
    return p_opts
end

NativeCif() = begin
    return NativeCif(Dict{String,NativeBlock}(),"")
end

NativeCif(s::AbstractString;verbose=false) = begin
    # get the full filename
    full = realpath(s)
    p_opts = default_options(full,verbose=verbose)
    result = cif_tp_ptr(p_opts)
    # the real result is in our user data context
    return NativeCif(p_opts.user_data.actual_cif,full)
end

"""Given a filename, parse and return a CIF object according to the provided options.
This is only tested with our walker functions, but will probably work for a
CIFAPI cif"""

cif_tp_ptr(p_opts::cif_parse_options)=begin
    # obtain an IOStream
    filename = p_opts.user_data.filename
    f = open(filename,"r")
    fptr = Base.Libc.FILE(f)
    ## Todo: finalizer for parse options
    dpp = cif_tp_ptr(0)   #value replaced by C library
    ## Debugging: do we have good values in our parse options context?
    ## println("User context is $(p_opts.user_data)")
    val=ccall((:cif_parse,"libcif"),Cint,(FILE,Ref{cif_parse_options},Ref{cif_tp_ptr}),fptr,p_opts,dpp)
    close(f)
    finalizer(cif_destroy!,dpp)
    # Check for errors and destroy the CIF if necessary
    if val != 0
        finalize(dpp)
        error("File $filename load error: "* error_codes[val])
    end
    #q = time_ns()
    #println("$q: Created cif ptr:$dpp for file $s")
    return dpp
end

