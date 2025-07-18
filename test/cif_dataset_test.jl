# Test CifDataset type

prepare_system() = begin

    #TODO: Make this a smaller version with only a few single-key, double-key
    # categories
    t = DDLm_Dictionary(joinpath(@__DIR__, "dictionaries", "mini_cif_pow.dic"))
    r = Cif(joinpath(@__DIR__, "reorg_test1.cif"))
    return t,r
end

@testset "CifSetProjection basics" begin

    t, r = prepare_system()
    sig = Dict("_pd_phase.id" => "crcuo2")
    csp = CifSetProjection(sig, t)
    @test haskey(csp, "_pd_phase.id")
    @test !(haskey(csp, "_pd_phase_mass.phase_id"))
    @test csp["_pd_phase.id"][] == "crcuo2"
    @test "_pd_phase.id" in keys(csp)
    @test length(csp, "pd_phase") == 1
end
