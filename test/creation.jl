# Test CIF object creation and destruction

testdir = @__DIR__

@testset "Test simple CIF creation and destruction" begin
    
    @test begin
    p = Cif(joinpath(testdir,"test_cifs","simple_data.cif"))
    b = p["simple_data"]
    t = b["_numb_su"]
    true
end

    @test begin
    p=Cif{CifBlock}()
    true    #if we succeed we are happy
end

    @test begin
        p = Cif()
        true
    end
    
    @test begin
    p=Cif(joinpath(testdir,"test_cifs","simple_data.cif"))
    true #if we succeed we are happy
end

    @test_throws Exception  Cif(joinpath(testdir,"test_cifs","bad_data.cif"))
end
