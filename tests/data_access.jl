# Data access tests
# This just sets up access to a particular block
prepare_block(filename,blockname) = begin
    t = cif(joinpath(@__DIR__,filename))
    b = t[blockname]
end

# Simple value tests
@testset "Simple data values" begin
    b = prepare_block("simple_data.cif","simple_data")
    @test String(b["_numb_su"]) == "0.0625(2)"
    @test String(b["_unquoted_string"]) == "unquoted"
    @test String(b["_text_string"]) == "text"
    @test Number(b["_numb_su"]) ≈ 0.0625
end

# Looped value tests
@testset "Looped values" begin
  b = prepare_block("simple_loops.cif","simple_loops")
  l = get_loop(b,"_col2")
  vals = []
  for p in l
      push!(vals,String(p["_col2"]))
  end
  @test Set(vals) == Set(["v1","v2","v3"])
end

# Test lists
@testset "List values" begin
b = prepare_block("list_data.cif","list_data")
l = cif_list(b["_digit_list"])
r = collect(l)
@test Number.(r) == [0,1,2,3,4,5,6,7,8,9]
end

# Test tables
@testset "Table values" begin
b = prepare_block("table_data.cif","table_data")
l = cif_table(b["_type_examples"])
@test Number(l["numb"])≈-123.4e+67
@test String(l["char"])=="char"
end

# Get the blocks
@testset "Block manipulations" begin
    t = cif(joinpath(@__DIR__,"simple_data.cif"))
    bl = get_all_blocks(t)
    @test get_block_code(bl[1]) == "simple_data"
end
