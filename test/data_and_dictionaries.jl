# Test combinations of data and dictionaries

prepare_dd() = begin
    t = DDLm_Dictionary(joinpath(@__DIR__, "dictionaries", "cif_core.dic"))
    n = first(Cif(joinpath(@__DIR__,"nick1.cif"))).second
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
    t = DDLm_Dictionary(joinpath(@__DIR__, "dictionaries", "multi_block_core.dic"))
    n = Cif(joinpath(@__DIR__,"nick1_mergeable.cif"))
    println("About to merge blocks")
    merge_blocks!(n,t)
    f = first(n).second
    @test length(f["_diffrn_radiation.type"]) == 2
    @test length(f["_reflns.apply_dispersion_to_fcalc"]) == 1
    @test haskey(f,"_atom_site.structure_id")
    @test length(unique(f["_atom_site.structure_id"])) == 2
    dids = f["_structure.id"]
    @test length(setdiff(unique(f["_cell.structure_id"]),dids)) == 0
end

#== Replace with CifDataset tests

@testset "DataDictBlock tests" begin
    c = Cif(joinpath(@__DIR__,"nick1.cif"))
    t = DDLm_Dictionary(joinpath(@__DIR__, "dictionaries", "cif_core.dic"))
    ddb = first(Cif{DataDictBlock}(c, t)).second

    @test guess_category("_space_group_symop.id", ddb) == "space_group_symop"
    @test guess_category("_local.local_not_actual_dataname", ddb) == "atom_type"
    @test guess_category("_dodgy.mcdodgy", ddb) === nothing

    ddb["_whatever.whatever"] = ["11", "12", "13"]
    add_to_loop!(ddb, "_atom_type_scat.symbol", "_whatever.whatever")
    @test "_whatever.whatever" in ddb.cat_lookup["atom_type_scat"]
    add_to_loop!(ddb, "_local.local_not_actual_dataname", "_whatever.whatever")
    @test "_whatever.whatever" in ddb.cat_lookup["atom_type"]
    @test !("_whatever.whatever" in ddb.cat_lookup["atom_type_scat"])
    create_loop!(ddb, ["_atom_type.symbol", "_local.local_not_actual_dataname"])
    @test guess_category("_local.local_not_actual_dataname", ddb) == "atom_type"
    CrystalInfoFramework.rename!(ddb, "_cell.length_a", "_cell.length_alpha")
    @test guess_category("_cell.length_alpha", ddb) == nothing
    @test !("_cell.length_a" in ddb.cat_lookup["cell"])

end
==#
