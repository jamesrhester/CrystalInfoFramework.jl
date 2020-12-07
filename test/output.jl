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

loop_
  _myname1
  _myname2
  _myname3
whatever 25.1 "who dares wins and so forth" ababab
;
   blah balh alahbladsk "yes" "no" what`ever ^442
;
   "@[]342"
"""

loadin() = begin
    t = open("testoutput.cif","w")
    write(t,text_cif)
    close(t)
    Cif("testoutput.cif")
end

@testset "Simple constructions" begin
    firstcif = loadin()
    t = open("new_testoutput.cif","w")
    show(t,MIME("text/cif"),firstcif)
    close(t)
    secondcif = Cif("new_testoutput.cif")
    old_b = firstcif["testblock"]
    new_b = secondcif["testblock"]
    for kv in ["_item1","_item2"]
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
