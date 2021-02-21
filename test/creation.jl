# Test CIF object creation and destruction
# Now adapted for NativeCif

testdir = @__PATH__

@testset "Test simple CIF creation and destruction" begin
    
    @test begin
    p = Cif(joinpath(testdir,"test_cifs","simple_data.cif"))
    b = p["simple_data"]
    t = b["_numb_su"]
    true
end

    @test begin
    p=Cif{CifValue,CifBlock{CifValue}}()
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
