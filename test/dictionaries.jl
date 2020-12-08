# Testing dictionary functionality

@testset "Testing dictionary access and construction" begin
    @test begin
        t = DDLm_Dictionary(joinpath(@__DIR__,"ddl.dic"))
        true
    end
    @test begin
        t = DDLm_Dictionary(joinpath(@__DIR__,"ddl.dic"))
        String(t["_alias.deprecation_date"][:type][!,:source][]) == "Assigned"
    end
end

prepare_system() = begin
    t = DDLm_Dictionary(joinpath(@__DIR__,"cif_mag.dic"))
end

@testset "DDLm_Dictionaries" begin
    t = prepare_system()
    @test "_audit_conform.dict_name" in get_names_in_cat(t,"audit_conform")
    @test "_atom_site.label" in get_keys_for_cat(t,"atom_site")
    @test "_atom_site_moment_crystalaxis" in get_names_in_cat(t,"atom_site_moment",aliases=true)
end

@testset "Importation" begin
    ud = prepare_system()
    @test String(ud["_atom_site_rotation.label"][:name][!,:linked_item_id][]) == "_atom_site.label"
    # everything has a definition
    @test nrow(ud[:definition][ismissing.(ud[:definition].id),:]) == 0
end

@testset "DDLm reference dictionaries" begin
    t = DDLm_Dictionary(joinpath(@__DIR__,"ddl.dic"))
    @test "_definition.master_id" in keys(t)
    @test t["_definition.master_id"][:definition].id[] == "_definition.master_id"
    @test find_name(t,"enumeration_set","master_id") == "_enumeration_set.master_id"
    @test find_object(t,"_type.master_id") == "master_id"
    @test "master_id" in get_objs_in_cat(t,"enumeration_set")
    @test "_units.master_id" in get_keys_for_cat(t,"units")
    @test get_linked_name(t,"_method.master_id") == "_definition.master_id"
end

@testset "DDL2 dictionaries" begin
    t = DDL2_Dictionary(joinpath(@__DIR__,"ddl2_with_methods.dic"))
    @test find_category(t,"_sub_category_examples.case") == "sub_category_examples"
    @test haskey(t,"_category.mandatory_code")
    @test get_keys_for_cat(t,"sub_category") == ["_sub_category.id"]
    @test "_dictionary_history.update" in get_names_in_cat(t,"dictionary_history")
    @test "revision" in get_objs_in_cat(t,"dictionary_history")
    load_func_text(t,"_item_default.value","Evaluation")
    load_func_text(t,"item_description","Evaluation")
    @test occursin("with e as enumeration",load_func_text(t,"_item_default.value","Evaluation"))
    @test occursin("loop d as description",load_func_text(t,"item_description","Evaluation"))
end

# Really just a syntax check at the moment.
@testset "Writing dictionaries" begin
    t = prepare_system()
    testout = open("testout.dic","w")
    show(testout,MIME("text/cif"),t)
    close(testout)
    new_t = DDLm_Dictionary("testout.dic")
    @test t["_atom_site_moment.Cartn"][:definition][!,:update][] == new_t["_atom_site_moment.Cartn"][:definition][!,:update][]
    #
    t = DDL2_Dictionary("cif_img_1.7.11.dic")
    testout = open("testout.dic","w")
    show(testout,MIME("text/cif"),t)
    close(testout)
    new_t = DDL2_Dictionary("testout.dic")
    @test t["_array_element_size.array_id"][:item][!,:category_id] == new_t["_array_element_size.array_id"][:item][!,:category_id]
end

@testset "Dictionary -> Julia type mapping" begin
    t = prepare_system()
    @test CrystalInfoFramework.convert_to_julia(t,"atom_site_Fourier_wave_vector","q1_coeff",["2"]) == [2]
    @test CrystalInfoFramework.convert_to_julia(t,"atom_site_moment","cartn",[["1.2","0.3","-0.5"]]) == [[1.2,0.3,-0.5]]
end
