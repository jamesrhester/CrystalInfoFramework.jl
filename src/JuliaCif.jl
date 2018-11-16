module JuliaCif
using Tables
#= This module provides ways of interacting with a Crystallographic Information
 file using Julia. It currently wraps the C CIF API.
=#

include("cif_errors.jl")
include("cif_base.jl")
include("cif_dic.jl")
include("drel.jl")

end
