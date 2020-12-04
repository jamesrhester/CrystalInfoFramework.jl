# Test CIF object creation and destruction
# Now adapted for NativeCif

testdir = @__DIR__

@testset "Test simple CIF creation and destruction" begin

@test begin
    p = Cif(joinpath(testdir,"simple_data.cif"))
    b = p["simple_data"]
    t = b["_numb_su"]
    true
end

@test begin
    p=Cif{CifValue}()
    true    #if we succeed we are happy
end

@test begin
    p=Cif(joinpath(testdir,"simple_data.cif"))
    true #if we succeed we are happy
end

end    #of testset
