module CrystalInfoFramework
using DataFrames
using FilePaths   #easy cross-platform URI
using URIParser
using Lerche #for native parser
using Libdl  #to find C library if present

# **Exports**

export CifValue,Cif,Block,CifBlock
export CifContainer, NestedCifContainer
export get_frames,get_contents
export get_loop, eachrow, add_to_loop!, create_loop!

# Base methods that we add to
import Base:keys,getindex,setindex!,length,haskey,iterate,get
import Base:delete!,show,first

# *Crystallographic Information Framework*
#
# See iucr.org for specifications.
#
# This package provides methods for reading and writing
# CIF files. A subpackage provides a data API that
# allows any file to be interpreted according to the
# CIF relational model.  This is used by CIF_dREL
# (a separate package) to execute dREL code on any
# dataset.
#
include("cif_errors.jl")
include("libcifapi.jl")
include("cif_base.jl")
include("cif2_transformer.jl")
include("cif_dic.jl")
include("caseless_strings.jl")
include("ddlm_dictionary_ng.jl")
include("ddl2_dictionary_ng.jl")
include("cif_output.jl")

"""
module DataContainer defines simple and complex
collections of tables (relations) for use with
CIF dictionaries.
"""
module DataContainer

using ..CrystalInfoFramework
using DataFrames

import Base: haskey,getindex,keys,show,iterate,length
import Base: isless

include("DataContainer/Types.jl")
include("DataContainer/DataSource.jl")
include("DataContainer/Relations.jl")

end

end
