#Testing CIF routines
using CrystalInfoFramework
using TidyTest
using DataFrames
using Lerche

# This just sets up access to a particular block
prepare_block(filename, blockname) = begin
    t = Cif(joinpath(@__DIR__, "test_cifs", filename))
    b = t[blockname]
end

@run_tests
