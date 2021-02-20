#Testing CIF routines
using CrystalInfoFramework
using Test
using DataFrames
using Lerche

# This just sets up access to a particular block
prepare_block(filename,blockname) = begin
    t = Cif(joinpath(@__DIR__,"test_cifs",filename))
    b = t[blockname]
end

include("creation.jl")
include("data_access.jl")
include("caseless_test.jl")
include("native_parser.jl")
include("save_frames.jl")
include("dictionaries.jl")
include("output.jl")

# Test DataContainers

include("dc_base.jl")
