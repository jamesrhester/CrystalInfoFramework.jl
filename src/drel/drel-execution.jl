#== This module defines an environment for executing dREL code
==#

module drel_exec
using JuliaCif

struct dynamic_block <: cif_block_with_dict
    cif::cif_block_with_dict
end

#== Initialise functions
==#
dynamic_block(c::cif_block_with_dict) = begin
    
end

Base.getindex(d::dynamic_block,s::String) = begin
    try
        q = d.cif[s]
    catch KeyError
        derive(d,s)
    end
end

derive(d::dynamic_block,s::String) = begin
    
end
