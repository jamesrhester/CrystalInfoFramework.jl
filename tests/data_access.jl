# Data access tests
# This just sets up access to a particular block
prepare_block(filename,blockname) = begin
    t = cif(joinpath(@__DIR__,filename))
    b = get_block(t,blockname)
end

# Simple value tests
@testset "Simple data values" begin
    b = prepare_block("simple_data.cif","simple_data")
    @test String(get_value(b,"_numb_su")) == "0.0625(2)"
    @test String(get_value(b,"_unquoted_string")) == "unquoted"
    @test String(get_value(b,"_text_string")) == "text"
    @test Number(get_value(b,"_numb_su")) ≈ 0.0625
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
# Get the blocks
@testset "Block manipulations" begin
    t = cif(joinpath(@__DIR__,"simple_data.cif"))
    bl = get_all_blocks(t)
    @test get_block_code(bl[1]) == "simple_data"
end
