#= This file provides the functions that interact directly with
the libcif API =#

export cif,cif_block,get_all_blocks,get_block_code
export get_loop,cif_list,cif_table
export get_save_frame, get_all_frames
export load_cif

import Base.Libc:FILE

"""
This represents the opaque cif_tp type.
"""
mutable struct cif_tp
end

"""A pointer to a cif_tp type managed by C"""
mutable struct cif_tp_ptr
    p::Ptr{cif_tp}
end

"""
A CIF object (may extend in the future)
"""
mutable struct cif
    handle::Ptr{cif_tp}
end

cif(x::cif_tp_ptr) = cif(x.p)

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

"""Construct a new CIF object"""
cif()= begin
    dpp = cif_tp_ptr(0)   #Null pointer will be replaced by C call
    val=ccall((:cif_create,"libcif"),Cint,(Ref{cif_tp_ptr},),Ref(dpp))
    # Can error-check val if necessary
    r = cif(dpp)
    #finalizer(cif_destroy!,r) #this will be called when finished
    println("Created cif ptr: $r for empty CIF")  #for debugging later
    return r
end

"""Parse input stream and return a CIF object"""
cif(f::IOStream) = begin
    error("Creating CIF from stream not yet implemented")
    # get the underlying file descriptor, turn it into a FILE*
    # then call...
end

"""An opaque type representing the parse options object in libcif"""
struct cif_parse_options
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
    ccall((:free,"libc"),Cvoid,(cpo_ptr,),x.handle)
end

"""Given a filename, parse and return a CIF object"""
cif(s::AbstractString)=begin
    # obtain an IOStream
    f = open(s,"r")
    fptr = Base.Libc.FILE(f)
    # create a parse options structure
    p_opts = cpo_ptr(0)
    ## Todo: finalizer for parse options
    val = ccall((:cif_parse_options_create,"libcif"),Cint,(Ref{cpo_ptr},),Ref(p_opts))
    dpp = cif_tp_ptr(0)   #value replaced by C library
    val=ccall((:cif_parse,"libcif"),Cint,(FILE,cpo_ptr,Ref{cif_tp_ptr}),fptr,p_opts,Ref(dpp))
    close(f)
    r = cif(dpp)
    finalizer(cif_destroy!,r)
    # Check for errors and destroy the CIF if necessary
    if val != 0
        finalize(r)
        error("File $s load error: "* error_codes[val])
    end
    #q = time_ns()
    #println("$q: Created cif ptr:$r for file $s")
    return r
end

#==
Routines for accessing parts of the CIF file
==#

#==
Data blocks
==#

"""The type of blocks and save frames"""

abstract type cif_container end

"""Without a dictionary we could have lists, tables or strings"""

get_dataname_type(c::cif_container,d::AbstractString) = begin
    return Any
end

"""An empty dummy container for when we havent kept track
of where a value comes from...may be removed with better
design"""

struct empty_cif_container <: cif_container end

"""An opaque type representing a CIF block"""
mutable struct cif_container_tp   #cif_block_tp in libcif
end

"""A pointer to a CIF block or save frame, set by libcif"""
mutable struct cif_container_tp_ptr
    handle::Ptr{cif_container_tp}  # *cif_block_tp
end


"""A simple wrapper for external use.

We must keep a reference to the CIF that contains this
block, otherwise it could be finalised once it is no
longer referenced in a program.  This will cause a
segmentation fault whenever the block is subsequently
referenced."""

struct cif_block <: cif_container
    handle::cif_container_tp_ptr   #*cif_container_tp
    cif_handle::cif                #keep a reference to this
end

container_destroy!(cb::cif_container_tp_ptr) =  begin
    #error_string = "Finalizing cif block ptr $cb"
    #t = @task println(error_string)
    #schedule(t)
    ccall((:cif_container_free,"libcif"),Cvoid,(Ptr{cif_container_tp},),cb.handle)
end

Base.getindex(c::cif,block_name::AbstractString) = begin
    cbt = cif_container_tp_ptr(0)
    bn_as_uchar = transcode(UInt16,block_name)
    append!(bn_as_uchar,0)
    val = ccall((:cif_get_block,"libcif"),Cint,(Ptr{cif_tp},Ptr{UInt16},Ptr{cif_container_tp_ptr}),
    c.handle,bn_as_uchar,Ref(cbt))
    # check val
    if val != 0
        error(error_codes[val])
    end
    finalizer(container_destroy!,cbt)
    #q = time_ns()
    #println("$q: Created cif block ptr: $cbt")
    return cif_block(cbt,c)
end

# Libcif requires a pointer to a location where it can store a pointer to an array of block handles.
# After the call our pointer points to the start of an array of pointers
mutable struct container_list_ptr
    handle::Ptr{cif_container_tp_ptr}  #**cif_block_tp
end

"""Get handles to all blocks in a data file"""
Base.values(c::cif) = begin
    array_address = container_list_ptr(0)  #**cif_block_tp
    #println("Array address before: $array_address")
    val = ccall((:cif_get_all_blocks,"libcif"),Cint,(Ptr{cif_tp},Ptr{container_list_ptr}),c.handle,Ref(array_address))
    if val!=0
        error(error_codes[val])
    end
    #println("Array address after: $array_address")
    if array_address.handle == C_NULL
        error("Unable to get block array address")
    end
    # Now count how many values we have
    n = 1
    b = unsafe_load(array_address.handle,n)
    #println("Start of actual array: $(b.handle)")
    while b.handle!=C_NULL
        n = n + 1
        b = unsafe_load(array_address.handle,n)
        #println("Ptr is $(b.handle)")
    end
    n = n - 1
    #println("Number of blocks: $n")
    # Total length is n
    block_list = Vector{cif_container_tp_ptr}(undef,n)
    for j=1:n
        block_list[j]=unsafe_load(array_address.handle,j)
        finalizer(container_destroy!,block_list[j])
    end
    # Now create an array of cif_blocks
    cif_blocks = Vector{cif_block}()
    for p in block_list
        push!(cif_blocks,cif_block(p,c))
    end
    return cif_blocks
end

"""Obtain the name of a frame or block"""
get_block_code(b::cif_container) = begin
    s = Uchar(0)
    val = ccall((:cif_container_get_code,"libcif"),Cint,(cif_container_tp_ptr,Ptr{Cvoid}),b.handle,Ref(s))
    if val != 0
        error(error_codes[val])
    end
    make_jl_string(s)
end

Base.keys(c::cif) = get_block_code.(values(c))

struct cif_frame <: cif_container
    handle::cif_container_tp_ptr
    parent::cif_container   #Stop garbage collection of the parent block
end


"""Get handles to all save frames in a data block"""
get_all_frames(b::cif_container) = begin
    array_address = container_list_ptr(0)  #**cif_block_tp
    #println("Array address before: $array_address")
    val = ccall((:cif_container_get_all_frames,"libcif"),Cint,(cif_container_tp_ptr,Ptr{container_list_ptr}),
        b.handle,Ref(array_address))
    if val!=0
        error(error_codes[val])
    end
    #println("Array address after: $array_address")
    if array_address.handle == C_NULL
        error("Unable to get save frame list address")
    end
    # Now count how many values we have
    n = 1
    f = unsafe_load(array_address.handle,n)
    #println("Start of actual array: $(b.handle)")
    while f.handle!=C_NULL
        n = n + 1
        f = unsafe_load(array_address.handle,n)
        #println("Ptr is $(b.handle)")
    end
    n = n - 1
    #println("Number of blocks: $n")
    # Total length is n
    block_list = Vector{cif_container_tp_ptr}(undef,n)
    for j=1:n
        block_list[j]=unsafe_load(array_address.handle,j)
        finalizer(container_destroy!,block_list[j])
    end
    # Now create an array of cif_blocks
    save_frames = Vector{cif_frame}()
    for p in block_list
        push!(save_frames,cif_frame(p,b))
    end
    return save_frames
end

get_save_frame(b::cif_container,s::AbstractString) = begin
    new_frame = cif_container_tp_ptr(0)
    uname = transcode(UInt16,s)
    append!(uname,0)
    q = time_ns()
    #println("$q: Transcoded to $uname")
    val = ccall((:cif_container_get_frame,"libcif"),Cint,(cif_container_tp_ptr,Ptr{UInt16},Ptr{cif_container_tp_ptr}),
    b.handle,uname,Ref(new_frame))
    if val != 0
        error(error_codes[val])
    end
    q = time_ns()
    #println("$q: Successfully found frame $name")
    #end
    #println("$q:Allocated new frame $new_val")
    finalizer(container_destroy!,new_frame)
    return cif_frame(new_frame,b)
end

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

Base.Number(t::cif_value_tp_ptr) = begin
    dd = Ref{Cdouble}(0)
    val = ccall((:cif_value_get_number,"libcif"),Cint,(Ptr{cif_value_tp},Ref{Cdouble}),t.handle,dd)
    if val != 0
        error(error_codes[val])
    end
    return dd[]
end

Base.Float64(t::cif_value_tp_ptr) = Base.Number(t)

Base.Integer(t::cif_value_tp_ptr) = begin
    i = Number(t)
    if !isinteger(i)
        InexactError(Integer,i)
    end
    return Integer(i)
end

Base.Array{T,1}(t::cif_value_tp_ptr) where {T <:Number} = begin
    a = cif_list(t)
    Number.(a)
end

Base.Array{T,2}(t::cif_value_tp_ptr) where {T <: Number} = begin
    a = cif_list(t)
    b = cif_list.(a)
    [Number.(c) for c in b]
end
#==
Base.convert(::Type{Array{cif_value_tp_ptr}},t::cif_value_tp_ptr) = begin
    cif_list(t)
end

Base.convert(::Type{Dict{String,cif_value_tp_ptr}},t::cif_value_tp_ptr) = begin
    cif_table(t)
end

Base.convert(::Type{Array{T}} where {T<:Number}, t::cif_value_tp_ptr) = begin
    p = cif_list(t)
    Number.(p)
end
==#

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
    elseif val_type == 4 return Missing
    elseif val_type == 5 return Nothing
    end
end
    
"""Return the value of an item"""
Base.getindex(b::cif_container,name::AbstractString) = begin
    new_val = cif_value_tp_ptr(0)
    uname = transcode(UInt16,name)
    append!(uname,0)
    q = time_ns()
    #println("$q: Transcoded to $uname")
    val = ccall((:cif_container_get_value,"libcif"),Cint,(cif_container_tp_ptr,Ptr{UInt16},Ptr{cif_value_tp_ptr}),
    b.handle,uname,Ref(new_val))
    if val != 0
        error("Error reading $name:"* error_codes[val])
    end
    q = time_ns()
    #println("$q: Successfully found value $name")
    #end
    #println("$q:Allocated new cif value $new_val")
    finalizer(value_free!,new_val)
    #Now type it up!
    new_type = get_dataname_type(b,name)
    if new_type == Any #try and do a little better
        new_type = get_syntactical_type(new_val) 
    end
    if typeof(new_val) != new_type
        return new_type(new_val)
    end
    return new_val
end

Base.get(b::cif_container,name::AbstractString,default) = begin
    retval = default
    try
        retval = b[name]
    catch
    end
    return retval
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

mutable struct cif_loop
    handle::cif_loop_tp_ptr
    length::Int             #to allow generators
    block::cif_container    #to avoid early garbage collection
end

mutable struct cif_loop_tp_ptr_ptr
    handle::Ptr{cif_loop_tp_ptr}
end
                
loop_free!(cl::cif_loop_tp_ptr) = begin
    ccall((:cif_loop_free,"libcif"),Cvoid,(Ptr{cif_loop_tp},),cl.handle)
end

cif_loop(handle,block) = begin
    # determine length
    final = cif_loop(handle,0,block)
    i = 0
    for x in final i=i+1 end
    #println("Loop has length $i")
    final.length = i
    return final
end

get_loop(b::cif_container,name) = begin
    loop = cif_loop_tp_ptr(0)
    utfname = transcode(UInt16,name)
    append!(utfname,0)
    val = ccall((:cif_container_get_item_loop,"libcif"),Cint,(cif_container_tp_ptr,Ptr{UInt16},Ptr{cif_loop_tp_ptr}),
     b.handle,utfname,Ref(loop))
    if val != 0
         error(error_codes[val])
    end
    finalizer(loop_free!,loop)
    return cif_loop(loop,b)
end

Base.keys(l::cif_loop) = begin
    ukeys = Uchar_list(0)
    val = ccall((:cif_loop_get_names,"libcif"),Cint,(cif_loop_tp_ptr,Ptr{Cvoid}),l.handle,Ref(ukeys))
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

# Return all datanames in the container. As all items belong to a loop, we get all loops,
# then get all keys in each loop.

Base.keys(c::cif_container) = begin
    llist = cif_loop_tp_ptr_ptr(0)
    val = ccall((:cif_container_get_all_loops,"libcif"),Cint,(cif_container_tp_ptr,Ptr{cif_loop_tp_ptr_ptr}),
                c.handle,Ref(llist))
    if val != 0
        error(error_codes[val])
    end
    if llist.handle == C_NULL
        error("Unable to get list of loops in block")
    end
    # Count values
    n = 1
    f = unsafe_load(llist.handle,n)
    while f.handle != C_NULL
        n = n + 1
        f = unsafe_load(llist.handle,n)
    end
    n = n - 1
    #println("Number of loops: $n")
    loop_list = Vector{cif_loop}(undef,n)
    for j = 1:n
        loop_list[j] = cif_loop(unsafe_load(llist.handle,j),c)
        finalizer(loop_free!,loop_list[j].handle)
    end
    # now get the keys
    keylist = []
    [append!(keylist,keys(l)) for l in loop_list]
    return keylist
end

#==
 Loop packets. These are not linked with other resources, so we do not
 need to keep a loop, block or CIF object alive while the packet is alive.
 ==#

struct cif_packet_tp
end

mutable struct cif_packet
    handle::Ptr{cif_packet_tp}
    parent::cif_container      #for type lookup
end

packet_free!(cif_packet) = begin
    val = ccall((:cif_packet_free,"libcif"),Cint,(Ptr{cif_packet_tp},),cif_packet.handle)
    if val != 0
        error(error_codes[val])
    end
end

# Note that values are freed when their packet is freed, so we do not need an
# explicit finalizer here
Base.getindex(p::cif_packet,key) = begin
    new_val = cif_value_tp_ptr(0)
    uname = transcode(UInt16,key)
    append!(uname,0)   #null terminated just in case
    val = ccall((:cif_packet_get_item,"libcif"),Cint,(Ptr{cif_packet_tp},Ptr{UInt16},Ptr{cif_value_tp_ptr}),
       p.handle,uname,Ref(new_val))
    if val == 35
        throw(KeyError(key))
    end
    if val != 0
        error(error_code[val])
    end
    new_type = get_dataname_type(p.parent,key)
    if new_type == Any
        new_type = get_syntactical_type(new_val)
    end
    if typeof(new_val) != new_type
        return new_type(new_val)
    end
    return new_val
end

# In order to broadcast over packets, we need to have a length
# We get the number of names and discard them!

Base.length(p::cif_packet) = begin
    ukeys = Uchar_list(0)
    val = ccall((:cif_packet_get_names,"libcif"),Cint,(Ptr{cif_packet_tp},Ptr{Cvoid}),p.handle,Ref(ukeys))
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
    while b.string!=C_NULL
        n = n + 1
        b = unsafe_load(ukeys.strings,n)
    end
    n = n - 1
    return n
end
#==
Loops can be iterated. However, a condition of the libcif API
is that iterators cannot iterate over the same loop, or over
separate loops, simulataneously. Therefore we have to pre-determine
the length in order for generator expressions to work.
==#

struct cif_pktitr_tp
end

mutable struct cif_pktitr_tp_ptr
    handle::Ptr{cif_pktitr_tp}
end

mutable struct loop_iterator
    handle::cif_pktitr_tp_ptr
    loop::cif_loop
end

close_pktitr!(t::cif_pktitr_tp_ptr) = begin
    #error_string = "Closing pktitr $t"
    #tt = @task println(error_string)
    #schedule(tt)
    val = ccall((:cif_pktitr_close,"libcif"),Cint,(Ptr{cif_pktitr_tp},),t.handle)
    if val != 0
        error(error_codes[val])
    end
end

Base.iterate(cl::cif_loop) = begin
    pktptr = cif_pktitr_tp_ptr(0)
    val = ccall((:cif_loop_get_packets,"libcif"),Cint,(cif_loop_tp_ptr,Ptr{cif_pktitr_tp_ptr}),
        cl.handle,Ref(pktptr))
    if val != 0
        error("Failed to get packet iterator for loop $(cl.handle):"* error_codes[val])
    end
    #println("New pktitr $pktptr for loop $(cl.handle)")
    finalizer(close_pktitr!,pktptr)
    final_iter = loop_iterator(pktptr,cl)
    # We should return the first item
    new_packet = cif_packet(0,cl.block)
    val = ccall((:cif_pktitr_next_packet,"libcif"),Cint,(cif_pktitr_tp_ptr,Ptr{cif_packet}),
        final_iter.handle,Ref(new_packet))
    # If iteration has finished already, return the appropriate Julia value
    if val > 1
        # remove the iterator
        error("Failed to get first packet: " * error_codes[val])
    end
    if val == 1
        println("Finalising $pktptr now")
        finalize(pktptr)
        return nothing
    end
    finalizer(packet_free!,new_packet)
    new_packet.parent = cl.block
    return (new_packet,final_iter)
end

Base.iterate(cl::cif_loop,pktitr) = begin
    # Make sure that the iterator belongs to the loop
    if pktitr.loop != cl
        error("Iterator $pktitr belongs to loop $(pktitr.cif_loop) not $cl!")
    end
    new_packet = cif_packet(0,cl.block)
    val = ccall((:cif_pktitr_next_packet,"libcif"),Cint,(cif_pktitr_tp_ptr,Ptr{cif_packet}),
        pktitr.handle,Ref(new_packet))
    if val > 1
        #println("Error, finalising $(pktitr.handle) now")
        finalize(pktitr.handle)
        error("Failed to get next packet :" * error_codes[val])
    end
    if val == 1
        #println("End, finalising $(pktitr.handle) now")
        finalize(pktitr.handle)
        return nothing
    end
    finalizer(packet_free!,new_packet)
    return (new_packet,pktitr)
end

Base.length(cl::cif_loop) = cl.length

"""Get the dataname type of the provided dataname, which should belong to the packet,
although this is not checked"""
get_dataname_type(cp::cif_packet,d::AbstractString) = begin
    return get_dataname_type(cp.parent,d)
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

#== CIF compound values ==#

struct cif_list
    handle::cif_value_tp_ptr
    parent::cif_container #for type information
    dataname::AbstractString #for type information
    length::Int  # for efficiency

    cif_list(cc::cif_container,dname::AbstractString,cv::cif_value_tp_ptr) = begin
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
        new(cv,cc,dname,elct)
    end
end

cif_list(t) = cif_list(empty_cif_container(),"",t)

#== Remember that we conventionally start at element 1 in Julia

This could fail miserably if we access the same value, then the garbage collector
frees it, then we access that value again...maybe?
==#

Base.iterate(cl::cif_list,el_num) = begin
    if cl.length < el_num
        return nothing
    end
    new_element = cif_value_tp_ptr(0)
    val = ccall((:cif_value_get_element_at,"libcif"),Cint,(Ptr{cif_value_tp},Cint,Ptr{cif_value_tp_ptr}),cl.handle.handle,el_num-1,Ref(new_element))
    if val != 0
        error(error_codes[val])
    end
    new_type = get_dataname_type(cl.parent,cl.dataname)
    if new_type == Any  #
        new_type = get_syntactical_type(new_element)
    end
    if typeof(new_element) != new_type
        return (new_type(new_element),el_num+1)
    end
    return (new_element,el_num+1)
end

Base.iterate(cl::cif_list) = begin
    iterate(cl,1)
end

Base.length(cl::cif_list) = cl.length
Base.eltype(::Type{cif_list}) = Any
Base.firstindex(::cif_list) = 1
Base.lastindex(cl::cif_list) = cl.length

# Turn into a list of strings

process_to_strings(c::cif_list,so_far::Vector{Any}) = begin
    for el in c
        t = get_syntactical_type(el)
        if t == cif_value_tp_ptr
            push!(so_far,String(t=el))
        elseif t in [cif_list,cif_table]
            push!(so_far,process_to_strings(el,Any[]))
        else push!(so_far,t(el))
        end
    end
    return so_far
end               
            
#== Table values
==#

struct cif_table
    handle::cif_value_tp_ptr
    parent::cif_container    #for type information
    dataname::AbstractString #for type information
    length::Int  # for efficiency

    cif_table(enclosing,dataname,cv::cif_value_tp_ptr) = begin
        cif_type = ccall((:cif_value_kind,"libcif"),Cint,(Ptr{cif_value_tp},),cv.handle)
        if cif_type != 3
            error("$val is not a cif table value")
        end
        elctptr = Ref{Cint}(0)
        val = ccall((:cif_value_get_element_count,"libcif"),Cint,(Ptr{cif_value_tp},Ptr{Cint}),cv.handle,elctptr)
        if val != 0
            error(error_codes[val])
        end
        elct = elctptr[]
        new(cv,enclosing,dataname,elct)
    end
end

cif_table(t) = cif_table(empty_cif_container(),"",t)

process_to_strings(c::cif_table,so_far::Dict{AbstractString,Any}) = begin
    for el in keys(c)
        t = get_syntactical_type(el)
        if t == cif_value_tp_ptr
            push!(so_far,String(t=el))
        elseif t in [cif_list,cif_table]
            push!(so_far,process_to_strings(el,Any[]))
        else push!(so_far,t(el))
        end
    end
    return so_far
end               

Base.keys(ct::cif_table) = begin
    ukeys = Uchar_list(0)
    q = time_ns()
    println("$q: accessing keys for $(ct.handle.handle)")
    val = ccall((:cif_value_get_keys,"libcif"),Cint,(Ptr{cif_value_tp},Ptr{Cvoid}),ct.handle.handle,Ref(ukeys))
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
    println("Start of actual array: $(b.string)")
    while b.string!=C_NULL
        n = n + 1
        b = unsafe_load(ukeys.strings,n)
        println("Ptr is $(b.string)")
    end
    n = n - 1
    println("Number of keys: $n")
    if n != ct.length
        error("Number of keys does not match stated length")
    end
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

Base.iterate(ct::cif_table,keys) = begin
    if length(keys) == 0
        return nothing
    end
    next_key = pop!(keys)
    return ct[next_key]
end

# To start the iteration we need a list of keys

Base.iterate(ct::cif_table) = begin
    iterate(ct,keys(ct))
end

Base.length(ct::cif_table) = ct.length

Base.getindex(ct::cif_table,key::AbstractString) = begin
    ukey = transcode(UInt16,key)
    append!(ukey,0)
    new_element = cif_value_tp_ptr(0)
    val = ccall((:cif_value_get_item_by_key,"libcif"),Cint,(Ptr{cif_value_tp},Ptr{UInt16},Ptr{cif_value_tp_ptr}),
        ct.handle.handle,ukey,Ref(new_element))
    if val == 73
        throw(KeyError(key))
        end
    if val != 0
        error(error_codes[val])
    end
    new_type = get_dataname_type(ct.parent,ct.dataname)
    if new_type == Any
        new_type = get_syntactical_type(new_element)
    end
    if typeof(new_element) != new_type
        return new_type(new_element)
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

#== Walking a CIF

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

struct NativeCif
    all_data::Dict{AbstractString,cif_container}
end

mutable struct NativeBlock <: cif_container
    save_frames::Dict{AbstractString,cif_container}
    loops::Vector{DataFrame}
end

mutable struct cif_builder_context
    cif::NativeCif
    apicif::cif
    current_block::AbstractString
    current_loop::Dict{AbstractString,Vector{Any}}
end

#== Cif walking functions
==#

handle_cif_start(a,b)::Cint = begin
    println("Cif started; nothing done")
    0
end

handle_cif_end(a,b)::Cint = begin
    println("Cif is finished")
    0
end


handle_block_start(a,b::cif_builder_context)::Cint = begin
    fc = cif_block(a,b.apicif)
    blockname = get_block_code(fc)
    b.current_block = blockname
    b.cif.all_data[blockname] = NativeBlock(Dict(),Vector())
    println("Current block is now $(b.current_block)")
    0
end


handle_block_end(a,b)::Cint = begin
    println("Block is finished")
    0
end


handle_frame_start(a,b)::Cint = begin
    println("Frame started; nothing done")
    0
end


handle_frame_end(a,b)::Cint = begin
    println("Frame is finished")
    0
end


handle_loop_start(a,b)::Cint = begin
    cl = cif_loop(a,b.apicif[b.current_block])
    b.current_loop = Dict()
    for k in keys(cl)
        b.current_loop[k]=Any[]
    end
    println("Loop started")
    0
end


handle_loop_end(a,b)::Cint = begin
    println("Loop is finished,creating data frame")
    df = DataFrame()
    for one_col in keys(b.current_loop)
        df[Symbol(one_col)] = b.current_loop[one_col]
    end
    push!(b.cif.all_data[b.current_block].loops,df)
    0
end


handle_packet_start(a,b)::Cint = begin
    println("Packet started; nothing done")
    0
end


handle_packet_end(a,b)::Cint = begin
    println("Packet is finished")
    0
end


handle_item(a::Ptr{UInt16},b::cif_value_tp_ptr,c)::Cint = begin
    a_as_uchar = Uchar(a)
    val = ""
    keyname = make_jl_string(a_as_uchar)
    println("Processing name $keyname")
    syntax_type = get_syntactical_type(b)
    if syntax_type == cif_value_tp_ptr
        val = String(b)
    elseif syntax_type == cif_list
        val = process_to_strings(b,Any[])
    elseif syntax_type == cif_table
        val = process_to_strings(b,Dict())
    else val = syntax_type()
    end
    push!(c.current_loop[keyname],val)
    return 0    
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

# This will eventually be folded into the initial read using the cif_parse_opts
# structure to load directly.

load_cif(c::cif) = begin
    starting_cif = NativeCif(Dict())
    context = cif_builder_context(starting_cif,c,"",Dict(),String[])
    handle_cif_start_c = @cfunction(handle_cif_start,Cint,(cif_tp_ptr,Ref{cif_builder_context}))
    handle_cif_end_c = @cfunction(handle_cif_end,Cint,(cif_tp_ptr,Ref{cif_builder_context}))
    handle_block_start_c = @cfunction(handle_block_start,Cint,(cif_container_tp_ptr,Ref{cif_builder_context}))
    handle_block_end_c = @cfunction(handle_block_end,Cint,(cif_container_tp_ptr,Ref{cif_builder_context}))
    handle_frame_start_c = @cfunction(handle_frame_start,Cint,(cif_container_tp_ptr,Ref{cif_builder_context}))
    handle_frame_end_c = @cfunction(handle_frame_end,Cint,(cif_container_tp_ptr,Ref{cif_builder_context}))
    handle_loop_start_c = @cfunction(handle_loop_start,Cint,(cif_loop_tp_ptr,Ref{cif_builder_context}))
    handle_loop_end_c = @cfunction(handle_loop_end,Cint,(cif_loop_tp_ptr,Ref{cif_builder_context}))
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
    val = ccall((:cif_walk,"libcif"),Cint,(Ptr{cif_tp},Ref{cif_handler_tp},Ref{cif_builder_context}),
                c.handle,Ref(handlers),Ref(context))
    if val != 0
        error("Failed to read in CIF:"*errorcodes[val])
    end
    return starting_cif
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
