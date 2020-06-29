
#== A CIF in Native Julia

Our Julia datastructure is built of a Dictionary of data blocks. A
data block is a List of Loops and a List of save frames, which are
themselves data blocks. A loop is a DataFrame. Single-valued items are
held in a loop with a single row.

==#

export CifValue,NativeCif,NativeBlock
export cif_container, nested_cif_container
export get_save_frame,get_frames,get_contents
export get_loop, eachrow, add_to_loop!, create_loop!,lookup_loop


"""
A container for CIF data. A dictionary which might remember where
it came from.
"""
abstract type cif_container{V} <: AbstractDict{String,V} end

get_source_file(c::cif_container) = error("Implement `get_source_file` for $(typeof(c))")
get_data_values(c::cif_container) = error("Implement `get_data_values` for $(typeof(c))")

"""
A basic type for input CIFS
"""
CifValue = Union{String,Missing,Nothing,Vector{T},Dict{String,T}} where T

Base.length(c::cif_container) = length(keys(c))
Base.keys(b::cif_container) = keys(get_data_values(b))
Base.haskey(b::cif_container,s::String) = haskey(get_data_values(b),lowercase(s))
Base.iterate(b::cif_container) = iterate(get_data_values(b))
Base.iterate(b::cif_container,s) = iterate(get_data_values(b),s)
Base.getindex(b::cif_container,s::String) = get_data_values(b)[lowercase(s)]
Base.get(b::cif_container,s::String,a) = get(get_data_values(b),lowercase(s),a)
get_datablock(b::cif_container) = b

# We can specify a particular row in a loop by giving the
# values of the datanames.
Base.getindex(b::cif_container,s::Dict) = begin
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

Base.setindex!(b::cif_container,v,s) = begin
    get_data_values(b)[lowercase(s)]=v
end

Base.delete!(b::cif_container,s) = begin
    delete!(get_data_values(b),lowercase(s))
end

"""
A container with nested blocks (save frames). These are returned by the
method `get_frames`. In all other ways a nested cif container behaves
as if the save frames are absent.
"""
abstract type nested_cif_container{V} <: cif_container{V} end

get_frames(c::nested_cif_container) = error("get_frames not implemented for $(typeof(c))")


"""
A CIF file is a cif_collection. The important distinction is that indexing produces a
cif_container, not an array of data values.  There are no values at the top level.
"""
abstract type CifCollection{V} <: AbstractDict{String,V} end

get_dataname_type(c::cif_container{V} where V, d::AbstractString) = begin
    return V
end

Base.show(io::IO,c::CifCollection) = begin
    for k in keys(c)
        write(io,"save_$k\n")
        show(io,c[k])
    end
end

struct NativeCif{V} <: CifCollection{V}
    contents::Dict{String,cif_container{V}}
    original_file::String
end

Base.keys(n::NativeCif) = keys(n.contents)
Base.first(n::NativeCif) = first(n.contents)
Base.length(n::NativeCif) = length(n.contents)
Base.haskey(n::NativeCif,s) = haskey(n.contents,s)
Base.getindex(n::NativeCif,s) = n.contents[s]
Base.setindex!(c::NativeCif,v,s) = begin
    c.contents[s]=v
end

Base.show(io::IO,c::NativeCif) = begin
    for k in keys(c)
        write(io,"data_$k\n")
        show(io,c[k])
    end
end

get_contents(n::NativeCif) = n.contents
get_source_file(n::NativeCif) = n.original_file

"""
We define both `NativeBlock`, which has no save frames, and
`FullBlock` which has save frames
"""
mutable struct NativeBlock{V} <: cif_container{V}
    loop_names::Vector{Vector{String}} #one loop is a list of datanames
    data_values::Dict{String,Vector{V}}
    original_file::String
end

NativeBlock{V}() where V = begin
    NativeBlock(Vector{String}[],Dict{String,Vector{V}}(),"")
end

mutable struct FullBlock{V} <: nested_cif_container{V}
    save_frames::Dict{String,cif_container{V}}
    loop_names::Vector{Vector{String}} #one loop is a list of datanames
    data_values::Dict{String,Vector{V}}
    original_file::String
end

NativeBlock(f::FullBlock) = NativeBlock(get_loop_names(f),get_data_values(f),get_source_file(f))
FullBlock(n::NativeBlock{V}) where V = FullBlock(Dict{String,cif_container{V}}(),get_loop_names(n),get_data_values(n),n.original_file)
FullBlock(f::FullBlock) = f

# And a simple access API
get_data_values(b::NativeBlock) = b.data_values
get_data_values(b::FullBlock) = b.data_values
set_data_values(b::NativeBlock,v) = begin b.data_values = v end
set_data_values(b::FullBlock,v) = begin b.data_values = v end

get_loop_names(b::NativeBlock) = b.loop_names
get_loop_names(b::FullBlock) = b.loop_names
set_loop_names(b::NativeBlock,n) = begin b.loop_names = n end
set_loop_names(b::FullBlock,n) = begin b.loop_names = n end

get_source_file(b::NativeBlock) = b.original_file
get_source_file(f::FullBlock) = f.original_file

# nested API
get_frames(f::FullBlock{V}) where V = NativeCif{V}(f.save_frames,get_source_file(f))
                  
# Show does not produce a conformant CIF (yet) but a
# quasi-CIF for informational purposes
Base.show(io::IO,c::cif_container) = begin
    write(io,"\n")
    key_vals = setdiff(collect(keys(c)),get_loop_names(c))
    for k in key_vals
        item = format_for_cif(first(c[k]))
        write(io,"$k\t$item\n")
    end
    
    # now go through the loops
    for one_loop in get_loop_names(c)
        write(io,"\nloop_\n")
        values = map(x -> getindex(c,x),one_loop)
        for o in one_loop
            write(io,"$o\n")
        end
        for value_pkt in zip(values...)
            for one_val in value_pkt
                write(io,"$(format_for_cif(one_val)) ")
            end
            write(io,"\n")
        end
    end
end

Base.show(io::IO,b::nested_cif_container) = begin
    # first output the save frames
    show(io,get_frames(b))
    show(io,NativeBlock(b))
end

# Obviously not CIF conformant as doesn't deal with internal inverted commas
format_for_cif(s::String) = "'$s'"

format_for_cif(l::Array) = "[\n"* join(format_for_cif.(l)," ") * "\n]"

format_for_cif(d::Dict) = begin
    outstring = "{"
    for k in keys(d)
        outstring *= "$k:$(format_for_cif(d[k])) "
    end
    return outstring * "}"
end

format_for_cif(n::Nothing) = "."
format_for_cif(n::Missing) = "?"
format_for_cif(a) = "#Unknown type below \n$a"

"""
    get_loop(b,s) -> DataFrame

Return the contents of the loop containing data name s in block
b. If no data are available, a zero-length DataFrame is returned.
"""
get_loop(b::cif_container,s) = begin
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

Convenience method: return the rows for which the requested data names
take the values provided in the dictionary.
"""
lookup_loop(b::cif_container,request::Dict{String,String}) = begin
    df = get_loop(b,first(request).first)
    for (k,v) in request
        df = df[df[Symbol(k)] .== v,:]
    end
    return df
end

"""
    add_to_loop!(b::cif_container, tgt, newname)

Add dataname `tgt` to the loop containing newname. Values for `tgt` must already
be present and have the same length as other values in the loop."""
add_to_loop!(b::cif_container, tgt, newname) = begin
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
    create_loop!(b::cif_container,names::Array{String,1})

Create a loop in ``b`` containing the datanames in ``names``.  Datanames assigned to
other loops are silently transferred to the new loop. All data attached to ``names`` 
should have the same length."""
create_loop!(b::cif_container,names::Array{String,1}) = begin
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

mutable struct cif_builder_context
    actual_cif::Dict{String,cif_container{CifValue}}
    block_stack::Array{cif_container{CifValue}}
    filename::String
    verbose::Bool
end

get_save_frame(c::FullBlock,s::String) = begin
    get_frames(c)[s]
end

#== Merge the save frame lists of the second block files into the
first block. This routine is used in order to merge
dictionaries, for which the data block contents are less important ==#

merge_saves(combiner::Function,c,d) = begin
    merged_saves = merge(combiner,get_frames(c),get_frames(d))
    FullBlock(merged_saves,get_loop_names(c),get_data_values(c),c.original_file)
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
    newblock = NativeBlock{CifValue}()
    newblock.original_file = b.filename
    push!(b.block_stack,newblock)
    0
end


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


handle_frame_start(a::cif_container_tp_ptr,b)::Cint = begin
    blockname = get_block_code(a)
    if b.verbose
        println("Frame started: $blockname")
    end
    newblock = NativeBlock{CifValue}()
    newblock.original_file = b.filename
    b.block_stack[end] = FullBlock(b.block_stack[end])
    push!(b.block_stack,newblock)
    0
end


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

NativeCif{V}() where V = begin
    return NativeCif(Dict{String,cif_container{V}}(),"")
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

