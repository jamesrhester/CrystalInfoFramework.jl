#==

    Copyright Australian Nuclear Science and Technology Organisation 2019-2021

    CrystalInfoFramework.jl is free software: you can redistribute it and/or
    modify it under the terms of the GNU General Public License as
    published by the Free Software Foundation, either version 3 of the
    License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see
    <https://www.gnu.org/licenses/>.

==#

""" *Crystallographic Information Framework*

 See iucr.org for specifications.

 This package provides methods for reading and writing
 CIF files. 
"""
module CrystalInfoFramework
using DataFrames
using URIs
using Lerche # for native parser
using PrecompileTools #for fast startup

# **Exports**

export Cif, Block, CifBlock
export cif_from_string
export CifContainer, NestedCifContainer
export get_frames, get_contents
export get_loop, eachrow, add_to_loop!, create_loop!, get_loop_names

# Base methods that we add to
import Base:keys, getindex, setindex!, length, haskey, iterate, get
import Base:delete!, show, first

include("cif_errors.jl")
include("cif_base.jl")
include("cif2_transformer.jl")
include("cif_dic.jl")
include("caseless_strings.jl")
include("ddlm_dictionary_ng.jl")
include("ddl2_dictionary_ng.jl")
include("data_with_dictionary.jl")
include("merge_blocks.jl")
include("cif_output.jl")

end
