# Test CifDataset type

prepare_system() = begin

    #TODO: Make this a smaller version with only a few single-key, double-key
    # categories
    t = DDLm_Dictionary(joinpath(@__DIR__, "dictionaries", "mini_cif_pow.dic"))
    r = Cif(joinpath(@__DIR__, "reorg_test1.cif"))
    return t,r
end

@testset "Utility routines" begin
    t, r = prepare_system()
    @test CrystalInfoFramework.has_implicit_only(r["cr2cuo4_7K"], t, "_space_group.id")
end

@testset "CifSetProjection basics" begin

    t, r = prepare_system()

    # First an empty CSP
    
    sig = Dict("_pd_phase.id" => "cr2cuo4")
    csp = CifSetProjection(sig, t)
    @test haskey(csp, "_pd_phase.id")
    @test !(haskey(csp, "_pd_phase_mass.phase_id"))
    @test !(is_allowed_cat(csp, "pd_phase_mass"))
    @test csp["_pd_phase.id"][] == "cr2cuo4"
    @test "_pd_phase.id" in keys(csp)
    @test length(csp, "pd_phase") == 1
    @test get_category_names(csp, "pd_phase") == ["_pd_phase.id"]
    @test get_category_names(csp, "pd_phase", non_set = true) == []
    @test has_category(csp, "pd_phase")
    @test get_loop_names(csp) == []

    # Now add an extra data name

    add_to_cat!(csp, "pd_phase", ["_pd_phase.name"],[["Cr2CuO4"]])
    @test length(csp, "pd_phase") == 1
    @test "_pd_phase.name" in keys(csp)
    @test haskey(csp, "_pd_phase.name")
    @test "_pd_phase.id" in get_category_names(csp, "pd_phase")

end

@testset "CifSetProjection loops" begin

    t, r = prepare_system()

    # Prepare a looped category

    sig = Dict("_space_group.id" => "fddd")
    csp = CifSetProjection(sig, t)
    add_to_cat!(csp, "space_group_symop",
                ["_space_group_symop.id", "_space_group_symop.operation_xyz"],
                 [["1", "2", "3"], ["x,y,z", "-x,1/4+y,1/4+z", "abc"]])
    @test length(csp, "space_group_symop") == 3
    @test haskey(csp, "_space_group_symop.id")
    @test haskey(csp, "_space_group_symop.space_group_id")
    @test csp["_space_group_symop.space_group_id"] == fill("fddd", 3)
    @test is_allowed_cat(csp, "space_group_wyckoff")
    @test !is_allowed_cat(csp, "pd_phase")
    @test !is_allowed_cat(csp, "structure")   #has a non-key link

    # Add some more values

    add_to_cat!(csp, "space_group_symop",
                ["_space_group_symop.id","_dodgy.dodge"],
                [["4","5"], ["3.14","59"]])

    @test length(csp, "space_group_symop") == 5

    p = (length(getindex(csp, n)) for n in get_category_names(csp, "space_group_symop", non_set = true))
    @test all( x-> x == 5, p)
    @test ismissing(csp["_dodgy.dodge"][2])
    @test "_dodgy.dodge" in get_category_names(csp, "space_group_symop")
    @test ismissing(csp["_space_group_symop.operation_xyz"][5])
    
end

@testset "CifDataset from block" begin

    t, r = prepare_system()
    cd = CifDataset(r, t)
    @test confirm_all_present(r, cd, t)

end
