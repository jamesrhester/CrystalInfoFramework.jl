# Test our native parser

const test_files_cif2 = ["bom_ver2.cif", "complex_data.cif",
                   "container_names.cif", "list_data.cif",
                   "simple_containers.cif", "simple_data.cif", "simple_loops.cif",
                   "table_data.cif", "text_fields.cif", "triple.cif",
                   "unicode.cif", "ver2.cif"]

const test_files_cif1 = ["comment_only.cif","cif11_unquoted.cif", "cif1_quoting.cif",
                   "empty.cif", "simple_data.cif", "simple_loops.cif"]

const test_fail_cif1 = ["cif1_invalid.cif"]

@testset "Native parse CIF1 files" begin
    for tf in test_files_cif1
        println("Testing $tf")
        Cif(joinpath(@__DIR__,"test_cifs",tf),native=true,version=1)
        @test true
    end
end

@testset "Native parse CIF2 files" begin
    for tf in test_files_cif2
        println("Testing $tf")
        Cif(joinpath(@__DIR__,"test_cifs",tf),native=true,version=2)
        @test true
    end
end

@testset "Invalid CIF1 files" begin
    for tf in test_fail_cif1
        @test_throws Lerche.UnexpectedCharacters Cif(joinpath(@__DIR__,"test_cifs",tf),native=true,version=1)
    end
end
