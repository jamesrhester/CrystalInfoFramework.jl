#= This file defines the basic methods for interaction with CIF files.

Note that the earlier methods define types and provide functions 
that interact directly with the libcif C API. The minimum required
are defined here, plus some no longer used destructors. Comprehensive
functions for working with a CIF held within the C API have been
removed. =#

export cif_tp_ptr,get_block_code
export get_loop,cif_list,cif_table, eachrow
export get_save_frame, get_all_frames
export NativeCif,NativeBlock

import Base.Libc:FILE

keep_alive = Any[]   #to stop GC freeing memory

"""
This represents the opaque cifapi cif_tp type.
"""
mutable struct cif_tp
end

"""A pointer to a cif_tp type managed by C"""
mutable struct cif_tp_ptr
    handle::Ptr{cif_tp}
end

"""A finalizer for a C-allocated CIF object"""
cif_destroy!(x) =  begin
    #q = time_ns()
    #error_string = "$q: Finalizing CIF object $x"
    #t = @task println(error_string)
    #schedule(t)
    val = ccall((:cif_destroy,"libcif"),Cint,(Ptr{cif_tp},),x.handle)
    if val != 0
        error(error_codes[val])
    end
end

struct cif_handler_tp
    cif_start::Ptr{Nothing}
    cif_end::Ptr{Nothing}
    block_start::Ptr{Nothing}
    block_end::Ptr{Nothing}
    frame_start::Ptr{Nothing}
    frame_end::Ptr{Nothing}
    loop_start::Ptr{Nothing}
    loop_end::Ptr{Nothing}
    packet_start::Ptr{Nothing}
    packet_end::Ptr{Nothing}
    handle_item::Ptr{Nothing}
end

#==
Data blocks
==#

"""An opaque type representing a CIF block"""
mutable struct cif_container_tp   #cif_block_tp in libcif
end

"""A pointer to a CIF block or save frame, set by libcif"""
mutable struct cif_container_tp_ptr
    handle::Ptr{cif_container_tp}  # *cif_block_tp
end

container_destroy!(cb::cif_container_tp_ptr) =  begin
    #error_string = "Finalizing cif block ptr $cb"
    #t = @task println(error_string)
    #schedule(t)
    ccall((:cif_container_free,"libcif"),Cvoid,(Ptr{cif_container_tp},),cb.handle)
end

get_block_code(b::cif_container_tp_ptr) = begin
    s = Uchar(0)
    val = ccall((:cif_container_get_code,"libcif"),Cint,(cif_container_tp_ptr,Ptr{Cvoid}),b,Ref(s))
    if val != 0
        error(error_codes[val])
    end
    make_jl_string(s)
end

Base.keys(c::cif_tp_ptr) = get_block_code.(values(c))

#==

   CIF values

   ==#

"""The general value type of a CIF file"""
mutable struct cif_value_tp
end

mutable struct cif_value_tp_ptr
    handle::Ptr{cif_value_tp}
end

# Do we have to finalize this? Yes indeedy.

value_free!(x::cif_value_tp_ptr) = begin
    #error_string = "Finalizing cif block ptr $cb"
    #t = @task println(error_string)
    #schedule(t)
    #q = time_ns()
    #error_string = "$q: Fly, be free $x"
    #t = @task println(error_string)
    #schedule(t)
    ccall((:cif_value_free,"libcif"),Cvoid,(Ptr{cif_value_tp},),x.handle)
end

Base.String(t::cif_value_tp_ptr) = begin
   #Get the textual representation
   s = Uchar(0)
   val = ccall((:cif_value_get_text,"libcif"),Cint,(Ptr{cif_value_tp},Ptr{Cvoid}),t.handle,Ref(s))
   if val != 0
       error(error_codes[val])
   end
   new_string = make_jl_string(s)
end

#== Use syntactical information to pin down the types a bit
==#

get_syntactical_type(t::cif_value_tp_ptr) = begin
    val_type = ccall((:cif_value_kind,"libcif"),Cint,(Ptr{cif_value_tp},),t.handle)
    if val_type == 0 || val_type == 1 return typeof(t)
    elseif val_type == 2 cif_list
    elseif val_type == 3 cif_table
    elseif val_type == 4 return Nothing
    elseif val_type == 5 return Missing
    end
end
    
#==
   Loops.

   We need to define loop types, packet types, and iteration over them

   ==#

mutable struct cif_loop_tp
end

mutable struct cif_loop_tp_ptr
    handle::Ptr{cif_loop_tp}
end
                
loop_free!(cl::cif_loop_tp_ptr) = begin
    ccall((:cif_loop_free,"libcif"),Cvoid,(Ptr{cif_loop_tp},),cl.handle)
end

Base.keys(l::Ptr{cif_loop_tp}) = begin
    ukeys = Uchar_list(0)
    val = ccall((:cif_loop_get_names,"libcif"),Cint,(Ptr{cif_loop_tp},Ptr{Cvoid}),l,Ref(ukeys))
    if val != 0
        error(error_codes[val])
    end
    # ukeys will actually be a **UInt16, that is, after return it will hold a pointer to an array of UInt16
    if ukeys.strings == C_NULL
        error("Unable to get key list address")
    end
    # Now count how many values we have
    n = 1
    b = unsafe_load(ukeys.strings,n)
    #println("Start of actual array: $(b.string)")
    while b.string!=C_NULL
        n = n + 1
        b = unsafe_load(ukeys.strings,n)
        #println("Ptr is $(b.string)")
    end
    n = n - 1
    #println("Number of keys: $n")
    # Load in the UChar string pointers
    ukey_list = Vector{Uchar}(undef,n)
    for j=1:n
        ukey_list[j]=unsafe_load(ukeys.strings,j)
    end
    # Now actually turn them into ordinary strings
    key_list = make_jl_string.(ukey_list)
    # println("Found loop values $key_list")
    return key_list
end
    

#==
 Loop packets. Only used as a pointer type for the callbacks
 ==#

struct cif_packet_tp
end


"""Utility routine to get the length of a C null-terminated array"""
get_c_length(s::Ptr,max=-1) = begin
    # Now loop over the values we have
    n = 1
    b = unsafe_load(s,n)
    while b!=0 && (max == -1 || (max != -1 && n < max))
        n = n + 1
        b = unsafe_load(s,n)
        #println("Char is $b")
    end
    n = n - 1
    #println("Length of string: $n")
    return n
end

cif_list(cv::cif_value_tp_ptr) = begin
    cif_type = ccall((:cif_value_kind,"libcif"),Cint,(Ptr{cif_value_tp},),cv.handle)
    if cif_type != 2
        error("$val is not a cif list value")
    end
    elctptr = Ref{Cint}(0)
    val = ccall((:cif_value_get_element_count,"libcif"),Cint,(Ptr{cif_value_tp},Ptr{Cint}),cv.handle,elctptr)
    if val != 0
        error(error_codes[val])
    end
    elct = elctptr[]
    so_far = Vector()
    for el_num in 1:elct
        new_element = cif_value_tp_ptr(0)
        val = ccall((:cif_value_get_element_at,"libcif"),Cint,(Ptr{cif_value_tp},Cint,Ptr{cif_value_tp_ptr}),cv.handle,el_num-1,Ref(new_element))
        if val != 0
            error(error_codes[val])
        end
        t = get_syntactical_type(new_element)
        if t == cif_value_tp_ptr
            push!(so_far,String(new_element))
        elseif t == cif_list
            push!(so_far,cif_list(new_element))
        elseif t == cif_table
            push!(so_far,cif_table(new_element))
        else push!(so_far,t())
        end
    end
    return so_far
end

cif_table(cv::cif_value_tp_ptr) = begin
    cif_type = ccall((:cif_value_kind,"libcif"),Cint,(Ptr{cif_value_tp},),cv.handle)
    if cif_type != 3
        error("$val is not a cif table value")
    end
    so_far = Dict{String,Any}()
    for el in keys(cv)
        new_val = cv[el]
        t = get_syntactical_type(new_val)
        if t == cif_value_tp_ptr
            so_far[el]=String(new_val)
        elseif t == cif_list
            so_far[el]=cif_list(new_val)
        elseif t == cif_table
            so_far[el]=cif_table(new_val)
        else so_far[el]=t()
        end
    end
    return so_far
end

# The pointer passed to us should point to a table
Base.keys(ct::cif_value_tp_ptr) = begin
    ukeys = Uchar_list(0)
    #q = time_ns()
    #println("$q: accessing keys for $(ct.handle.handle)")
    val = ccall((:cif_value_get_keys,"libcif"),Cint,(Ptr{cif_value_tp},Ptr{Cvoid}),ct.handle,Ref(ukeys))
    if val != 0
        error(error_codes[val])
    end
    # ukeys will actually be a **UInt16, that is, after return it will hold a pointer to an array of UInt16
    if ukeys.strings == C_NULL
        error("Unable to get key list address")
    end
    # Now count how many values we have
    n = 1
    b = unsafe_load(ukeys.strings,n)
    # println("Start of actual array: $(b.string)")
    while b.string!=C_NULL
        n = n + 1
        b = unsafe_load(ukeys.strings,n)
        #println("Ptr is $(b.string)")
    end
    n = n - 1
    #println("Number of keys: $n")
    # Load in the UChar string pointers
    ukey_list = Vector{Uchar}(undef,n)
    for j=1:n
        ukey_list[j]=unsafe_load(ukeys.strings,j)
    end
    # Now actually turn them into ordinary strings
    # This is not strictly necessary in the context of iteration
    # but will probably help in debugging and error messages
    key_list = make_jl_string.(ukey_list)
end

# Access the value through the C library
Base.getindex(ct::cif_value_tp_ptr,key::AbstractString) = begin
    ukey = transcode(UInt16,key)
    append!(ukey,0)
    new_element = cif_value_tp_ptr(0)
    val = ccall((:cif_value_get_item_by_key,"libcif"),Cint,(Ptr{cif_value_tp},Ptr{UInt16},Ptr{cif_value_tp_ptr}),
        ct.handle,ukey,Ref(new_element))
    if val == 73
        throw(KeyError(key))
        end
    if val != 0
        error(error_codes[val])
    end
    return new_element
end

"""The type external Unicode strings from libicu"""
mutable struct Uchar
    string::Ptr{UInt16}
end

"""A list of strings"""
mutable struct Uchar_list
    strings::Ptr{Uchar}
end

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

struct NativeCif <: Cif{cif_container{String}}
    contents::Dict{String,cif_container}
    original_file::String
end

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

Base.keys(b::NativeBlock) = keys(b.data_values)
Base.haskey(b::NativeBlock,s::String) = haskey(b.data_values,lowercase(s))
Base.iterate(b::NativeBlock) = iterate(b.data_values)
Base.iterate(b::NativeBlock,s) = iterate(b.data_values,s)
Base.length(b::NativeBlock) = length(b.data_values)
Base.getindex(b::NativeBlock,s::String) = b.data_values[lowercase(s)]
Base.get(b::NativeBlock,s::String,a) = get(b.data_values,lowercase(s),a)

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

mutable struct cif_builder_context
    actual_cif::Dict{String,cif_container}
    block_stack::Array{cif_container}
    filename::String
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
    #println("New blockname $(blockname)")
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
    #println("Frame started")
    blockname = get_block_code(a)
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
    #println("Loop is finished,recording packets")
    push!(b.block_stack[end].loop_names,keys(a))
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
    #println("Processing name $keyname")
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
    #==if !ismissing(val) && val != nothing
        println("With value $val")
    elseif ismissing(val)
        println("With value ?")
    else println("With value .")
    end ==#
    lc_keyname = lowercase(keyname)
    if !(lc_keyname in keys(current_block.data_values))
        current_block.data_values[lc_keyname] = [val]
    else
        push!(current_block.data_values[lc_keyname],val)
    end
    return 0    
end

default_options(s::String) = begin
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
    context = cif_builder_context(Dict(),cif_container[],s)
    p_opts = cif_parse_options(0,C_NULL,0,0,0,1,C_NULL,C_NULL,Ref(handlers),C_NULL,C_NULL,C_NULL,C_NULL,context)
    return p_opts
end

NativeCif() = begin
    return NativeCif(Dict{String,NativeBlock}(),"")
end

NativeCif(s::AbstractString) = begin
    # get the full filename
    full = realpath(s)
    p_opts = default_options(full)
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

#== Utilities
==#
# TODO: if this is used to make keys for a CIF table,
# we segfault if "own" is true. Why is that, and can
# we fix it
"""Turning an ICU string into a Jula string"""
make_jl_string(s::Uchar) = begin
    n = get_c_length(s.string,-1)  # short for testing
    icu_string = unsafe_wrap(Array{UInt16,1},s.string,n,own=false)
    block_code = transcode(String,icu_string)
end
