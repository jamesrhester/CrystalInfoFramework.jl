using CrystalInfoFramework
using Measurements
using Unitful

parse_cif_value(x) = measurement(x)

function cif_geometry(file)
    cif = only(Cif(file))[2]

    atoms = Symbol.(cif["_atom_site_type_symbol"])
    fract_x = parse_cif_value.(cif["_atom_site_fract_x"])
    fract_y = parse_cif_value.(cif["_atom_site_fract_y"])
    fract_z = parse_cif_value.(cif["_atom_site_fract_z"])
    fract = permutedims(hcat(fract_x, fract_y, fract_z))

    a, b, c = map(["a", "b", "c"]) do dim
        return parse_cif_value(only(cif["_cell_length_$dim"])) * u"Å"
    end

    α, β, γ = map(["alpha", "beta", "gamma"]) do angle
        return parse_cif_value(only(cif["_cell_angle_$angle"])) * u"°"
    end

    # Transformation matrix according to
    # https://chemistry.stackexchange.com/questions/136836/converting-fractional-coordinates-into-cartesian-coordinates-for-crystallography
    n2 = (cos(α) - cos(γ)*cos(β)) / sin(γ)

    M = [
        a 0u"Å" 0u"Å" ;
        b*cos(γ) b*sin(γ) 0u"Å" ;
        c*cos(β) c*n2 c*sqrt(sin(β)^2 - n2^2)
    ]

    return atoms, M' * fract
end

# Some data from the Crystallography Open Database (COD), ID 7706719
file = "7706719.cif"

atoms, geometry = cif_geometry(file)