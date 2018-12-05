#Testing dREL runtime support
using JuliaCif

prepare_system() = begin
    t = cifdic(joinpath(@__DIR__,"cif_mag.dic"))
    u = cif(joinpath(@__DIR__,"AgCrS2.mcif"))
    ud = assign_dictionary(u["AgCrS2_OG"],t)
end

@testset "Testing CategoryObject functionality" begin
    ud = prepare_system()
    c = CategoryObject(ud,"atom_site_moment")
    f = c[Dict("_atom_site_moment.label"=>"Cr1_2")]
    @test f["_atom_site_moment.crystalaxis_y"] == 2.33
end
