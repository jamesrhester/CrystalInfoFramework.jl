ALL: jl_transformer.py 

%.py: %.nw
	notangle $< > $@
#
validation_builtins.jl: jl_transformer.nw
	notangle -RValidation_functions $< > $@
#
