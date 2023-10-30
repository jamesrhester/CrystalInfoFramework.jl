# Test combinations of data and dictionaries

prepare_dd() = begin
    t = DDLm_Dictionary(joinpath(@__PATH__,"cif_core.dic"))
    n = first(Cif(joinpath(@__PATH__,"nick1.cif"))).second
    return t,n
end

is_looped(b, n) = any(x -> n in x, CrystalInfoFramework.get_loop_names(b))

@testset "Data with dictionaries" begin

    # Check simple utilities
    
    t, n = prepare_dd()
    @test has_category(n, "cell", t)
    @test !has_category(n,"geom_angle", t)
    ln = CrystalInfoFramework.get_loop_names(n, "refln", t)
    @test setdiff(ln, ["_refln.index_h",                   
                       "_refln.index_k",                  
                       "_refln.index_l",
                       "_refln.f_meas",                    
                       "_refln.f_calc"]) == []

    # Check that we can loop set items
    
    @test !is_looped(n, "_cell.length_a")
    make_set_loops!(n, t)
    @test is_looped(n, "_cell.length_a")
    l = get_loop(n, "_cell.length_a")
    @test "_cell.volume" in names(l)
    @test count_rows(n, "cell", t) == 1

    # Add missing keys

    n["_diffrn.id"] = ["xyz"]
    add_child_keys!(n, "_diffrn.id", t)
    @test n["_cell.diffrn_id"] == ["xyz"]

end

@testset "Merging blocks" begin
    t = DDLm_Dictionary(joinpath(@__PATH__,"cif_core.dic"))
    n = Cif(joinpath(@__PATH__,"nick1_mergeable.cif"))
    println("About to merge blocks")
    merge_blocks!(n,t)
    f = first(n).second
    @test length(f["_diffrn_radiation.type"]) == 2
    @test length(f["_reflns.apply_dispersion_to_fcalc"]) == 1
    @test haskey(f,"_atom_site.diffrn_id")
    @test length(unique(f["_atom_site.diffrn_id"])) == 2
    dids = f["_diffrn.id"]
    @test length(setdiff(unique(f["_cell.diffrn_id"]),dids)) == 0
end
