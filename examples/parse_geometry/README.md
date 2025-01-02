# Parsing CIF geometry

The file `parse_geometry.jl` defines the function `cif_geometry(path)` that
reads a geometry from a CIF file and returns

- A list of element symbol, e.g. `:C` for a carbon atom, in
  a format that is compatible with the `PeriodicTable.jl` and `Mendeleeiev.jl` packages to look up properties of the elements.
- A `3 x n_atoms` array of the position.
  The array elements are `Measurement`s of `Unitful` quantities,
  therefore both the uncertainty given in the CIF file
  and the units are carried with the geometry.
  The uncertainties and units can be dropped using, respectively,
  `Measurements.value.(geometry)` and `ustrip.(geometry)`.

To use the file directly,
make the `examples/parse_geometry/` folder the working
directory (usually using the `cd` terminal command).

The example requires the `Measurements`, `Unitful` and `CrystalInfoFramework`
packages.
You can either install them manually
(by typing `] add Measurements Unitful CrystalInforFramework` in julia REPL)
or use the example environment
(by starting julia as `julia --project`
while being in the `examples/parse_geometry/` folder
and then typing `] instantiate` in julia REPL).

To run as a command line program from the folder, type `julia --project parse_geometry.jl <filename>`,
where `<filename>` is a CIF file. If `<filename>` is missing, the supplied example
file from the COD is used.

To run interactively from the folder, type `julia --project`, then at the prompt `include("parse_geometry.jl")`,
then `cif_geometry(<path>)`.
