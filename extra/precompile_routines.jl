# Precompile everything needed
# julia> PackageCompiler.create_sysimage(["CrystalInfoFramework","Lerche","DataFrames"]; sysimage_path = <output>
# precompile_execution_file = "extra/precompile_routines.jl")
#
# Then execute julia: julia -J<path_to_output> for no compilation time! 
#
import CrystalInfoFramework
include(joinpath(pkgdir(CrystalInfoFramework),"test","runtests.jl"))
