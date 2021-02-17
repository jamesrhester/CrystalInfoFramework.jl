# Pre-build the cif2 grammar to save load time

using Lerche
using Serialization

include("../src/cif2.ebnf")
include("../src/cif1.ebnf")

lark_grammar() = begin
    ll = Lerche.Lark(_cif1_grammar_spec,start="input",parser="lalr",lexer="contextual")
    mm = Lerche.Lark(_cif2_grammar_spec,start="input",parser="lalr",lexer="contextual")
    return ll,mm
end

Serialization.serialize(joinpath(@__DIR__,"cif_grammar_serialised.jli"),lark_grammar())
