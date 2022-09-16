#Testing CIF routines
using CrystalInfoFramework
using Test
using DataFrames
using Lerche
using FilePaths

# This just sets up access to a particular block
prepare_block(filename,blockname;native=false) = begin
    t = Cif(joinpath(@__PATH__,"test_cifs",filename),native=native)
    b = t[blockname]
end


#include("creation.jl")
#include("data_access.jl")
#include("caseless_test.jl")
#include("native_parser.jl")
#include("save_frames.jl")
#include("dictionaries.jl")
include("data_and_dictionaries.jl")
#include("output.jl")


# Test DataContainers

#include("dc_base.jl")
