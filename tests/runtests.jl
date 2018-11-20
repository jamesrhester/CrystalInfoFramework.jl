#Testing CIF routines
using JuliaCif
using Test
# This just sets up access to a particular block
prepare_block(filename,blockname) = begin
    t = cif(joinpath(@__DIR__,filename))
    b = t[blockname]
end

include("creation.jl")
#include("data_access.jl")
#include("save_frames.jl")
#include("dictionaries.jl")
#include("drel_test.jl")
