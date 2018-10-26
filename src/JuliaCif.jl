module JuliaCif
#= This module provides ways of interacting with a Crystallographic Information
 file using Julia. It currently wraps the C CIF API.
=#
export cif,cif_block,get_all_blocks,get_block_code
export get_all_blocks,get_loop,cif_list,cif_table


include("cif_errors.jl")

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
    cif()
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
    val = ccall((:cif_parse_options_create,"libcif"),Cint,(Ref{cpo_ptr},),Ref(p_opts))
    dpp = cif_tp_ptr(0)   #value replaced by C library
    val=ccall((:cif_parse,"libcif"),Cint,(FILE,cpo_ptr,Ref{cif_tp_ptr}),fptr,p_opts,Ref(dpp))
    close(f)
    # can check val here
    if val != 0
        error(error_codes[val])
    end
    r = cif(dpp)
    finalizer(cif_destroy!,r)
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

"""An opaque type representing a CIF block"""
mutable struct cif_block_tp   #cif_block_tp in libcif
end

"""A pointer to a CIF block, set by libcif"""
mutable struct cif_block_tp_ptr
    handle::Ptr{cif_block_tp}  # *cif_block_tp
end

"""A simple wrapper for external use.

We must keep a reference to the CIF that contains this
block, otherwise it could be finalised once it is no
longer referenced in a program.  This will cause a
segmentation fault whenever the block is subsequently
referenced."""
struct cif_block
    handle::cif_block_tp_ptr   #*cif_block_libcif
    cif_handle::cif            #keep a reference to this
end

cb_destroy!(cb::cif_block_tp_ptr) =  begin
    #error_string = "Finalizing cif block ptr $cb"
    #t = @task println(error_string)
    #schedule(t)
    ccall((:cif_container_free,"libcif"),Cvoid,(Ptr{cif_block_tp},),cb.handle)
end

Base.getindex(c::cif,block_name::AbstractString) = begin
    cbt = cif_block_tp_ptr(0)
    bn_as_uchar = transcode(UInt16,block_name)
    append!(bn_as_uchar,0)
    val = ccall((:cif_get_block,"libcif"),Cint,(Ptr{cif_tp},Ptr{UInt16},Ptr{cif_block_tp_ptr}),
    c.handle,bn_as_uchar,Ref(cbt))
    # check val
    if val != 0
        error(error_codes[val])
    end
    finalizer(cb_destroy!,cbt)
    #q = time_ns()
    #println("$q: Created cif block ptr: $cbt")
    return cif_block(cbt,c)
end

# Libcif requires a pointer to a location where it can store a pointer to an array of block handles.
# After the call our pointer points to the start of an array of pointers
mutable struct block_list_ptr
    handle::Ptr{cif_block_tp_ptr}  #**cif_block_tp
end

"""Get handles to all blocks in a data file"""
get_all_blocks(c::cif) = begin
    array_address = block_list_ptr(0)  #**cif_block_tp
    #println("Array address before: $array_address")
    val = ccall((:cif_get_all_blocks,"libcif"),Cint,(Ptr{cif_tp},Ptr{block_list_ptr}),c.handle,Ref(array_address))
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
    block_list = Vector{cif_block_tp_ptr}(undef,n)
    for j=1:n
        block_list[j]=unsafe_load(array_address.handle,j)
        finalizer(cb_destroy!,block_list[j])
    end
    # Now create an array of cif_blocks
    cif_blocks = Vector{cif_block}()
    for p in block_list
        push!(cif_blocks,cif_block(p,c))
    end
    return cif_blocks
end

"""The type external Unicode strings from libicu"""
mutable struct Uchar
    string::Ptr{UInt16}
end

"""Turning an ICU string into a Jula string"""
make_jl_string(s::Uchar) = begin
    n = get_c_length(s.string,-1)  # short for testing
    icu_string = unsafe_wrap(Array{UInt16,1},s.string,n,own=true)
    block_code = transcode(String,icu_string)
end

"""Obtain the name of a block"""
get_block_code(b::cif_block) = begin
    s = Uchar(0)
    val = ccall((:cif_container_get_code,"libcif"),Cint,(cif_block_tp_ptr,Ptr{Cvoid}),b.handle,Ref(s))
    if val != 0
        error(error_codes[val])
    end
    make_jl_string(s)
end

"""The general value type of a CIF file"""
mutable struct cif_value_tp
end

mutable struct cif_value_tp_ptr
    handle::Ptr{cif_value_tp}
end

# Do we have to finalize this? Yes indeedy.

value_free!(x::cif_value_tp_ptr) = begin
    ccall((:cif_value_free,"libcif"),Cvoid,(Ptr{cif_value_tp},),x.handle)
end

# Now define conversions
Base.Number(t::cif_value_tp_ptr) = begin
    dd = Ref{Cdouble}(0)
    val = ccall((:cif_value_get_number,"libcif"),Cint,(Ptr{cif_value_tp},Ref{Cdouble}),t.handle,dd)
    if val != 0
        error(error_codes[val])
    end
    return dd[]
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

"""Return the value of an item"""
Base.getindex(b::cif_block,name::AbstractString) = begin
    new_val = cif_value_tp_ptr(0)
    uname = transcode(UInt16,name)
    append!(uname,0)
    q = time_ns()
    #println("$q: Transcoded to $uname")
    val = ccall((:cif_container_get_value,"libcif"),Cint,(cif_block_tp_ptr,Ptr{UInt16},Ptr{cif_value_tp_ptr}),
    b.handle,uname,Ref(new_val))
    if val != 0
        error(error_codes[val])
    end
    q = time_ns()
    #rintln("$q: Successfully found value $name")
    #end
    finalizer(value_free!,new_val)
    return new_val
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
    block::cif_block    #to avoid early garbage collection
end

loop_free!(cl::cif_loop_tp_ptr) = begin
    ccall((:cif_loop_free,"libcif"),Cvoid,(Ptr{cif_loop_tp},),cl.handle)
end

get_loop(b::cif_block,name) = begin
    loop = cif_loop_tp_ptr(0)
    utfname = transcode(UInt16,name)
    append!(utfname,0)
    val = ccall((:cif_container_get_item_loop,"libcif"),Cint,(cif_block_tp_ptr,Ptr{UInt16},Ptr{cif_loop_tp_ptr}),
     b.handle,utfname,Ref(loop))
    if val != 0
         error(error_codes[val])
    end
    finalizer(loop_free!,loop)
    return cif_loop(loop,b)
end

#==
 Loop packets. These are not linked with other resources, so we do not
 need to keep a loop, block or CIF object alive while the packet is alive.
 ==#

struct cif_packet_tp
end

mutable struct cif_packet
    handle::Ptr{cif_packet_tp}
end

packet_free!(cif_packet) = begin
    val = ccall((:cif_packet_free,"libcif"),Cint,(Ptr{cif_packet_tp},),cif_packet.handle)
    if val != 0
        error(error_codes[val])
    end
end

Base.getindex(p::cif_packet,key) = begin
    new_val = cif_value_tp_ptr(0)
    uname = transcode(UInt16,key)
    append!(uname,0)   #null terminated just in case
    val = ccall((:cif_packet_get_item,"libcif"),Cint,(Ptr{cif_packet_tp},Ptr{UInt16},Ptr{cif_value_tp_ptr}),
       p.handle,uname,Ref(new_val))
    if val == 35
        KeyError(key)
    end
    if val != 0
        error(error_code[val])
    end
    return new_val
end

#==
Loops can be iterated
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
        error(error_codes[val])
    end
    finalizer(close_pktitr!,pktptr)
    final_iter = loop_iterator(pktptr,cl)
    # We should return the first item
    new_packet = cif_packet(0)
    val = ccall((:cif_pktitr_next_packet,"libcif"),Cint,(cif_pktitr_tp_ptr,Ptr{cif_packet}),
        final_iter.handle,Ref(new_packet))
    # If iteration has finished already, return the appropriate Julia value
    if val > 1
        error(error_codes[val])
    end
    if val == 1
        return nothing
    end
    finalizer(packet_free!,new_packet)
    return (new_packet,final_iter)
end

Base.iterate(cl,pktitr) = begin
    # Make sure that the iterator belongs to the loop
    if pktitr.loop != cl
        error("Iterator $pktitr belongs to loop $(pktitr.cif_loop) not $cl!")
    end
    new_packet = cif_packet(0)
    val = ccall((:cif_pktitr_next_packet,"libcif"),Cint,(cif_pktitr_tp_ptr,Ptr{cif_packet}),
        pktitr.handle,Ref(new_packet))
    if val > 1
        error(error_codes[val])
    end
    if val == 1
        return nothing
    end
    finalizer(packet_free!,new_packet)
    return (new_packet,pktitr)
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
    length::Int  # for efficiency

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
        new(cv,elct)
    end
end

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
    return (new_element,el_num+1)
end

Base.iterate(cl::cif_list) = begin
    iterate(cl,1)
end

Base.length(cl::cif_list) = cl.length
Base.eltype(::Type{cif_list}) = cif_value_tp_ptr
Base.firstindex(::cif_list) = 1
Base.lastindex(cl::cif_list) = cl.length

#== Table values
==#

struct cif_table
    handle::cif_value_tp_ptr
    length::Int  # for efficiency

    cif_table(cv::cif_value_tp_ptr) = begin
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
        new(cv,elct)
    end
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
    ukeys = UChar(0)
    val = ccall((:cif_value_get_keys,"libcif"),Cint,(Ptr{cif_value_tp},Ptr{UInt16}),cl.handle.handle,Ref(ukeys))
    if val != 0
        error(error_codes[val])
    end
    # ukeys will actually be a **UInt16, that is, after return it will hold a pointer to an array of UInt16
    if ukeys.handle == C_NULL
        error("Unable to get key list address")
    end
    # Now count how many values we have
    n = 1
    b = unsafe_load(ukeys.handle,n)
    #println("Start of actual array: $(b.handle)")
    while b.handle!=C_NULL
        n = n + 1
        b = unsafe_load(array_address.handle,n)
        #println("Ptr is $(b.handle)")
    end
    n = n - 1
    #println("Number of keys: $n")
    if n != ct.length
        error("Number of keys does not match stated length")
    end
    # Load in the UChar string pointers
    ukey_list = Vector{UChar}(undef,n)
    for j=1:n
        key_list[j]=unsafe_load(ukeys.handle,j)
    end
    # Now actually turn them into ordinary strings
    # This is not strictly necessary in the context of iteration
    # but will probably help in debugging and error messages
    key_list = make_jl_string.(ukey_list)
    iterate(ct,key_list)
end

Base.length(ct::cif_table) = ct.length

Base.getindex(ct::cif_table,key::AbstractString) = begin
    ukey = transcode(UInt16,key)
    append!(ukey,0)
    new_element = cif_value_tp_ptr(0)
    val = ccall((:cif_value_get_item_by_key,"libcif"),Cint,(Ptr{cif_value_tp},Ptr{UInt16},Ptr{cif_value_tp_ptr}),
        ct.handle.handle,ukey,Ref(new_element))
    if val == 73
        KeyError(key)
        end
    if val != 0
        error(error_codes[val])
    end
    return new_element
end

greet() = print("Hello World!")

end # module
