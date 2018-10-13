# Test CIF file creation and destruction
@testset "Test simple CIF creation and destruction" begin

@test p=CIF();true    #if we succeed we are happy

@test p=CIF("simple_data.cif");true #if we succeed we are happy

end;
