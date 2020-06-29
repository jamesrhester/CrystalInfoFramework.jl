module CrystalInfoFramework
using DataFrames
using URIParser
#= This module provides ways of interacting with a Crystallographic Information
 file using Julia.
=#

include("cif_errors.jl")
include("libcifapi.jl")
include("cif_base.jl")
include("cif_dic.jl")
include("ddl2_dictionary.jl")

end
