# Testing dictionary functionality

@testset "Testing dictionary access and construction" begin
    @test begin
        t = Cifdic(joinpath(@__DIR__,"ddl.dic"))
        true
    end
    @test begin
        t = Cifdic(joinpath(@__DIR__,"ddl.dic"))
        String(t["_alias.deprecation_date"]["_type.source"][1]) == "Assigned"
    end
    @test begin
        t = Cifdic(joinpath(@__DIR__,"ddl.dic"))
        String(get_by_cat_obj(t,("Type","Contents"))["_definition.class"][1]) == "Attribute"
    end
end

prepare_system() = begin
    t = Cifdic(joinpath(@__DIR__,"cif_mag.dic"))
end

@testset "Importation" begin
    ud = prepare_system()
    @test String(ud["_atom_site_rotation.label"]["_name.linked_item_id"][1]) == "_atom_site.label"
end

@testset "DDL2 dictionaries" begin
    t = DDL2_Dictionary(joinpath(@__DIR__,"ddl_core_2.1.3.dic"))
    @test find_category(t,"_sub_category_examples.case") == "sub_category_examples"
    @test haskey(t,"_category.mandatory_code")
    @test get_keys_for_cat(t,"sub_category") == ["_sub_category.id"]
end
