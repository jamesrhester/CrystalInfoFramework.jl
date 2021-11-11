# Test CIF output

# Add any tough output constructions
# to the following text string.

const text_cif = """
data_testblock
   _item1 non-delimited-string
   _item2 
;
    Fancy string with stuff in it
;
   _Item3 'case should not matter'

loop_
  _myName1
  _myname2
  _myname3
whatever 25.1 "who dares wins and so forth" ababab
;
   blah balh alahbladsk "yes" "no" what`ever ^442
;
   "@[]342"
"""

loadin() = begin
    Cif(text_cif)   #native parser
end

@testset "Simple constructions" begin
    firstcif = loadin()
    t = open("new_testoutput.cif","w")
    show(t,MIME("text/cif"),firstcif)
    close(t)
    secondcif = Cif(p"new_testoutput.cif")
    old_b = firstcif["testblock"]
    new_b = secondcif["testblock"]
    for kv in ["_item1","_item2","_item3"]
        @test old_b[kv] == new_b[kv]
    end
    # test loops by indexing with _myname1
    lk = old_b["_myname1"]
    iv = indexin(lk,new_b["_myname1"])
    for one_ind in 1:length(lk)
        for one_name in ["_myname2","_myname3"]
            @test old_b[one_name][one_ind] == new_b[one_name][iv[one_ind]]
        end
    end
end

@testset "Individual values" begin
    @test format_for_cif(2.5) == "2.5"
    @test format_for_cif(11) == "11"
    one_line = "this is a single line"
    @test format_for_cif(one_line) == "'$one_line'"
    tricky_line = "this line has a carriage \n return and an ' so tricky"
    @test format_for_cif(tricky_line) == "\n;$tricky_line\n;"
    really_tricky = "this line has \n; and ''' oh dear"
    @test format_for_cif(really_tricky) == "\n;>\\\n>this line has \n>; and ''' oh dear\n;"
    really_tricky = "this line has \n; and \"\"\" oh dear"
    @test format_for_cif(really_tricky) == "\n;>\\\n>this line has \n>; and \"\"\" oh dear\n;"
    @test format_for_cif("_atom_site_u_iso_or_equiv") == "'_atom_site_u_iso_or_equiv'"
    @test format_for_cif("data_validation_number") == "'data_validation_number'"
end

@testset "Straight in and out" begin
    @test begin show(stdout,MIME("text/cif"),Cif(joinpath(@__PATH__,"nick1.cif")));true end
    @test begin show(stdout,MIME("text/cif"),Cif(joinpath(@__PATH__,"nick1.cif"),native=true));true end
end
