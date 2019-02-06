module JuliaCif
using DataFrames
using URIParser
#= This module provides ways of interacting with a Crystallographic Information
 file using Julia. It currently wraps the C CIF API.
=#

include("cif_errors.jl")
include("cif_base.jl")
include("cif_dic.jl")
include("drel/drel.jl")
include("drel/drel_ast.jl")
include("drel/drel-execution.jl")
include("drel/drel_runtime.jl")

end
