# Testing dictionary functionality

@testset "Testing dictionary access and construction" begin
    @test begin
        t = DDLm_Dictionary(joinpath(@__PATH__,"ddl.dic"))
        true
    end
    @test begin
        t = DDLm_Dictionary(joinpath(@__PATH__,"ddl.dic"))
        String(t["_alias.deprecation_date"][:type][!,:source][]) == "Assigned"
    end
end

prepare_system() = begin
    t = DDLm_Dictionary(joinpath(@__PATH__,"cif_mag.dic"))
end


@testset "DDLm_Dictionaries" begin
    t = prepare_system()
    @test "_audit_conform.dict_name" in get_names_in_cat(t,"audit_conform")
    @test "_atom_site.label" in get_keys_for_cat(t,"atom_site")
    @test "_atom_site_moment_crystalaxis" in get_names_in_cat(t,"atom_site_moment",aliases=true)
    # Test child names
    t = DDLm_Dictionary(joinpath(@__PATH__,"cif_core.dic"))
    @test lowercase(find_name(t,"atom_site","matrix_U")) == "_atom_site_aniso.matrix_u"
    @test Set(get_keys_for_cat(t,"atom_site",aliases=true)) == Set(["_atom_site.label","_atom_site_label"])
    @test length(get_linked_names_in_cat(t,"geom_bond")) == 2
    @test "cell" in get_set_categories(t)
    @test "geom_bond" in get_loop_categories(t)
    @test get_single_keyname(t,"atom_site") == "label"
    @test_throws Exception get_single_keyname(t,"geom_bond")
    @test ("atom_site","_atom_site.label") in get_single_key_cats(t)
    @test get_ultimate_link(t,"_geom_bond.atom_site_label_1") == "_atom_site.label"
    @test get_default(t,"_geom_angle.publ_flag") == "no"
    @test ismissing(get_default(t,"_space_group_symop.T")) 
    @test get_dimensions(t,"model_site","adp_eigen_system") == [4,3]
    @test CrystalInfoFramework.get_container_type(t,"_model_site.adp_eigen_system") == "Array"
    @test find_head_category(t[:name]) == "cif_core"
    struct dummy_packet
        symbol::CaselessString
    end
    @test lookup_default(t,"_atom_type.atomic_mass",dummy_packet("Ag")) == "107.868"
    @test "radius_contact" in as_data(t)["_name.object_id"]
end

@testset "Dictionary updating" begin
    t = DDLm_Dictionary(joinpath(@__PATH__,"ddl.dic"))
    @test update_dict!(t,"_enumeration.default","_type.purpose","Encode","XXX")
    @test t["_enumeration.default"][:type].purpose[] == "XXX"
    @test !update_dict!(t,"_units.code","_type.source","XXX","YYY")
    # what about changing the definition name
    update_dict!(t,"_type.source","_definition.id","_type.saucy")
    @test t["_type.saucy"][:name].object_id[] == "source"
    # what if this is a new column in a one-row category
    update_dict!(t,"_type.contents","_definition.whatever","all new")
    @test t["_type.contents"][:definition].whatever[] == "all new"
    # what if this is an altogether new category
    update_dict!(t,"_name.object_id","_newcat.whichever","hello")
    @test t["_name.object_id"][:newcat].whichever[] == "hello"
    # adding a definition
    old_def = t["_definition.class"]
    new_def_name = "_onetwothree.four"
    old_def[:name].object_id = ["four"]
    old_def[:name].category_id = ["onetwothree"]
    old_def[:definition].id = [new_def_name]
    old_def[:definition].update = ["2022-01-11"]
    old_def[:definition].text = ["Please edit me"]
    add_definition!(t,old_def)
    @test t[new_def_name][:name].category_id[] == "onetwothree"
    @test t[new_def_name][:definition].text[] == "Please edit me"
    @test t["_definition.class"][:name].category_id[] == "definition"
    # replacement of category
    t = DDLm_Dictionary(joinpath(@__PATH__,"cif_core.dic"))
    rename_category!(t,"atom_site","new_atom_site")
    @test t["_new_atom_site.attached_hydrogens"][:name].object_id[] == "attached_hydrogens"
    @test lowercase(t["_new_atom_site.b_equiv_geom_mean_su"][:name].linked_item_id[]) == "_new_atom_site.b_equiv_geom_mean"
    @test t["_new_atom_site.Cartn_x"][:name].category_id[] == "new_atom_site"
    @test t["new_atom_site"][:definition].scope[] == "Category"
    @test t["atom_site_aniso"][:name].category_id[] == "new_atom_site"
end

# process imports

@testset "Importation" begin
    ud = prepare_system()
    @test String(ud["_atom_site_rotation.label"][:name][!,:linked_item_id][]) == "_atom_site.label"
    # everything has a definition
    @test nrow(ud[:definition][ismissing.(ud[:definition].id),:]) == 0
    @test get_parent_category(ud,"structure") == "magnetic"
    # try importing through alternative directory, we've changed update date.
    uf = DDLm_Dictionary(joinpath(@__PATH__,"small_core_test.dic"),
                         import_dir=joinpath(@__PATH__,"other_import_dir"))
    @test String(uf["_diffrn_orient_matrix.UB_11"][:definition][!,:update][]) == "2021-12-07" 
end

@testset "Introspecting imports" begin
    ud = DDLm_Dictionary(joinpath(@__PATH__,"cif_mag.dic"),ignore_imports=true)
    @test check_import_block(ud,"_atom_site_rotation.label",:name,:linked_item_id,"_atom_site.label")
    @test !check_import_block(ud,"_atom_site_rotation.label",:type,:purpose,"Junk")
end

@testset "Function-related tests for DDLm" begin
    t = DDLm_Dictionary(joinpath(@__PATH__,"cif_core.dic"))
    ff = get_dict_funcs(t)
    @test ff[1] == "function"
    @test "atomtype" in ff[2]
    one_meth = """_atom_type.radius_contact =  _atom_type.radius_bond + 1.25"""
    @test strip(load_func_text(t,"_atom_type.radius_contact","Evaluation")) == strip(one_meth)
    set_func!(t,"myfunc",:(x->x+2),eval(:(x->x+2)))
    @test occursin("x + 2","$(get_func_text(t,"myfunc"))")
    @test get_func(t,"myfunc")(2) == 4
    # default methods
    set_func!(t,"myattrfunc","_units.code",:(x -> "radians"),eval(:(x->"radians")))
    @test occursin("radians","$(get_def_meth_txt(t,"myattrfunc","_units.code"))")
    @test get_def_meth(t,"myattrfunc","_units.code")("whatever") == "radians"
end

@testset "Function-related tests for DDL2" begin
    t = DDL2_Dictionary(joinpath(@__PATH__,"ddl2_with_methods.dic"))
    ff = get_dict_funcs(t)
    @test ff[1] == nothing
    @test length(ff[2]) == 0
    one_meth = "item.category_id = name[item.name].category_id"
    @test strip(load_func_text(t,"_item.category_id","Evaluation")) == strip(one_meth)
    set_func!(t,"myfunc",:(x->x+2),eval(:(x->x+2)))
    @test occursin("x + 2","$(get_func_text(t,"myfunc"))")
    @test get_func(t,"myfunc")(2) == 4
    @test occursin("with e as enumeration",load_func_text(t,"_item_default.value","Evaluation"))
    @test occursin("loop d as description",load_func_text(t,"item_description","Evaluation"))
end

@testset "DDLm reference dictionaries" begin
    t = DDLm_Dictionary(joinpath(@__PATH__,"ddl.dic"))
    @test "_definition.master_id" in keys(t)
    @test t["_definition.master_id"][:definition].id[] == "_definition.master_id"
    @test find_name(t,"enumeration_set","master_id") == "_enumeration_set.master_id"
    @test find_object(t,"_type.master_id") == "master_id"
    @test "master_id" in get_objs_in_cat(t,"enumeration_set")
    @test "_units.master_id" in get_keys_for_cat(t,"units")
    @test get_linked_name(t,"_method.master_id") == "_definition.master_id"
    @test "dictionary_audit" in CrystalInfoFramework.find_top_level_cats(t)
end

@testset "DDL2 dictionaries" begin
    t = DDL2_Dictionary(joinpath(@__PATH__,"ddl2_with_methods.dic"))
    @test find_category(t,"_sub_category_examples.case") == "sub_category_examples"
    @test haskey(t,"_category.mandatory_code")
    @test get_keys_for_cat(t,"sub_category") == ["_sub_category.id"]
    @test "_dictionary_history.update" in get_names_in_cat(t,"dictionary_history")
    @test "revision" in get_objs_in_cat(t,"dictionary_history")
    @test get_dic_name(t) == "mmcif_ddl.dic"
    @test get_dic_namespace(t) == "ddl2"
    t = DDL2_Dictionary(joinpath(@__PATH__,"cif_img_1.7.11.dic"))
    @test list_aliases(t,"_diffrn_detector.details") == ["_diffrn_detector_details"]
    @test length(intersect(list_aliases(t,"_diffrn_detector.details",include_self=true),
                           ["_diffrn_detector_details","_diffrn_detector.details"])) == 2
    @test find_name(t,"_diffrn_detector_details") == "_diffrn_detector.details"
    @test find_name(t,"_diffrn_measurement.device") == "_diffrn_measurement.device"
    @test get_parent_name(t,"_diffrn_measurement_axis.measurement_device") == "_diffrn_measurement.device"
    @test "detector bins" in as_data(t)["_item_enumeration.detail"]
    @test get_julia_type_name(t,"axis","type") == (:CaselessString,"Single")
    @test get_julia_type_name(t,"array_element_size","size") == (Float64,"Single")
    @test get_default(t,"_axis.type") == "general"
end

# Really just a syntax check at the moment.
@testset "Writing dictionaries" begin
    t = prepare_system()
    testout = open("testout.dic","w")
    show(testout,MIME("text/cif"),t)
    close(testout)
    new_t = DDLm_Dictionary(p"testout.dic")
    @test t["_atom_site_moment.Cartn"][:definition][!,:update][] == new_t["_atom_site_moment.Cartn"][:definition][!,:update][]
    # This sometimes gets left out
    @test t["_atom_site_fourier_wave_vector.q1_coeff"][:type].contents[] == "Integer"
    #
    t = DDL2_Dictionary(joinpath(@__PATH__,"cif_img_1.7.11.dic"))
    testout = open("testout.dic","w")
    show(testout,MIME("text/cif"),t)
    close(testout)
    new_t = DDL2_Dictionary(p"testout.dic")
    @test t["_array_element_size.array_id"][:item][!,:category_id] == new_t["_array_element_size.array_id"][:item][!,:category_id]
end

@testset "Dictionary -> Julia type mapping" begin
    t = prepare_system()
    @test CrystalInfoFramework.convert_to_julia(t,"atom_site_Fourier_wave_vector","q1_coeff",["2"]) == [2]
    @test CrystalInfoFramework.convert_to_julia(t,"atom_site_moment","cartn",[["1.2","0.3","-0.5"]]) == [[1.2,0.3,-0.5]]
    @test CrystalInfoFramework.Range("5:7") == (5,7)
end
