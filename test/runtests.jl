#Testing CIF routines
using CrystalInfoFramework
using Test
using DataFrames

# This just sets up access to a particular block
prepare_block(filename,blockname) = begin
    t = NativeCif(joinpath(@__DIR__,filename))
    b = t[blockname]
end

include("creation.jl")
include("data_access.jl")
include("save_frames.jl")
include("dictionaries.jl")
