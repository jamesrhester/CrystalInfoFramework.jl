# **Routines for outputting CIF values

export format_for_cif

"""
    format_for_cif(val)

Format the provided value for output in a CIF2
file. Generally CIF1 and CIF2 syntaxes are
identical for non-text values.  CIF2 syntax
is preferred where the result is also conformant
CIF1 syntax with the same meaning.
"""
function format_for_cif end

"""
    format_for_cif(val::AbstractString;cif1=false)

Return `val` formatted as a text string for output in
a CIF2 file.  Line folding and prefixing is not used.

If `cif1`, triple-quoted strings
will never be output, but output will fail if the
supplied string contains the "\n;" digraph.  For `cif1`,
non-ASCII code points in `val` are output despite
this being a violation of the CIF1 standard.
"""
format_for_cif(val::AbstractString;cif1=false) = begin
    if '\n' in val
        if occursin("\n;",val)
            if cif1
                throw(error("$val cannot be formatted using CIF1 syntax"))
            end
            if occursin("'''",val)
                delimiter = "\"\"\""
            else
                delimiter = "'''"
            end
        else
            delimiter = "\n;"
        end
    else
        if '"' in val
            if '\'' in val
                delimiter = "\n;"
            else
                delimiter = "'"
            end
        else
            if '\'' in val
                delimiter = "\n;"
            elseif length(val) == 0
                delimiter = "'"
            elseif first(val) == '_'
                delimiter = "'"
            else
                q = match(r"^data|^save|^global|^loop",String(val))
                if !isnothing(q) delimiter = "'"
                else
                    q = match(r"\S+",String(val))
                    if !isnothing(q) && q.match == val delimiter = ""
                    else
                        delimiter = "'"
                    end
                end
            end
        end
    end
    return delimiter*val*delimiter
end

format_for_cif(val::Real) = begin
    return "$val"
end

format_for_cif(val::Missing) = "?"
format_for_cif(val::Nothing) = "."

format_for_cif(val::Array) = begin
    outstring = IOBuffer()
    write(outstring,"[")
    line_pos = 1
    for item in val
        value = format_for_cif(item)*" "
        if '\n' in value
            line_pos = length(value) - findlast(isequal('\n'),value)
            write(outstring, value)
        else
            if length(value) + line_pos + 1 > 80
                write(outstring,"\n")
                write(outstring,value)
                line_pos = length(value)
            else
                write(outstring, value)
                line_pos = line_pos + length(value)
            end
        end
    end
    return String(take!(outstring)[1:(end-1)])*']'
end

format_for_cif(val::Dict) = begin
    outstring = IOBuffer()
    write(outstring,"{")
    line_pos = 1
    for (k,v) in val
        mini_val = "\"$k\":$(format_for_cif(v)) "
        if '\n' in mini_val
            line_pos = length(mini_val) - findlast(isequal('\n'),mini_val)
            write(outstring, mini_val)
        else
            if length(mini_val) + line_pos + 1 > 80
                write(outstring,"\n")
                write(outstring,mini_val)
                line_pos = length(mini_val)
            else
                write(outstring, mini_val)
                line_pos = line_pos + length(mini_val)
            end
        end
    end
    return String(take!(outstring)[1:(end-1)])*'}'
end

"""
If passed a DataFrame we format a loop. If passed an additional name for
the category, each column name is prefixed by this name. `indent` contains
the indent for the loop list and the indent for key-value items, where
the latter is used when there is only one item in the loop and it would
fit in an 80-character line. Columns are output in `order`, and then
alphabetical order for anything not in `order`.
"""
format_for_cif(df::DataFrame;catname=nothing,indent=[0,33],order=()) = begin
    outstring = IOBuffer()
    inpad = " "^indent[1]
    write(outstring,inpad*"loop_\n")
    outname = ""
    if catname != nothing
        outname = "_"*catname*"."
    end
    # remove missing columns
    colnames = setdiff(sort!(propertynames(df)),order)
    final_list = filter(collect(Iterators.flatten((order,colnames)))) do n
        !(all(x->ismissing(x),df[!,n]))
    end
    for n in final_list
        write(outstring,inpad*"  "*outname*String(n)*"\n")
    end
    stringified, widths, loop_indent = calc_loop_spacing(df)
    loop_indent = min(loop_indent,indent[2])
    inpad = ' '^loop_indent
    write(outstring,inpad)
    line_pos = loop_indent
    for one_row in eachrow(stringified)
        for n in final_list
            w = getproperty(widths[1,:],n)
            #if all(x->ismissing(x),df[!,n]) continue end
            new_val = getproperty(one_row,n)
            if '\n' in new_val   # assume will start a new line
                line_pos = length(new_val) - findlast(isequal('\n'),new_val)+1
                write(outstring,new_val*' ')
            else
                if length(new_val) + line_pos + 2 > 80
                    write(outstring,"\n"*inpad)
                    line_pos = loop_indent
                    write(outstring,new_val)
                    write(outstring,' '^(w-length(new_val)))
                    line_pos = line_pos + w
                else
                    write(outstring,new_val)
                    write(outstring,' '^(w-length(new_val)))
                    line_pos = line_pos + w
                end
            end
        end
        write(outstring,"\n"*inpad)
        line_pos = loop_indent
    end
    String(take!(outstring))[1:end-loop_indent]
end

"""
    calc_loop_spacing(df::DataFrame)

Work out appropriate spacing for each column. To save doing it
twice, return `df` with entries formatted for output.
"""
calc_loop_spacing(df::DataFrame) = begin
    # remove missing
    wantnames = [n for n in names(df) if any(x->!ismissing(x),df[!,n])]
    stringified = mapcols(x->format_for_cif.(x),select(df,wantnames))
    # work out the widest entry for each column
    widths = mapcols(stringified) do x
        f = filter(n -> !occursin('\n',n),x)
        if length(f) > 0
            maximum(length.(f)) + 1
        else
            0
        end
    end
    maxwidth = sum(widths[1,:])
    # distribute empty space
    empty_space = max(0,round(Int,80-maxwidth))
    extra = round(Int,empty_space/(ncol(widths)+1))
    widths = mapcols!(widths) do x
        if x[1] == 0 0
        else
            x[1]+extra
        end
    end
    return stringified,widths,extra
end

# Default order for outputting DDLm categories
const ddlm_cat_order = (:definition,:alias,:description,:name,:type,:import,:description_example)
const ddlm_def_order = Dict(:definition=>(:id,:scope),:type=>(:purpose,:source),
                            :name => (:category_id,:object_id))
"""
    show_one_def(io,def_name,info_dic;implicits=[])

Convert one dictionary definition for `def_name` to text. 
`info_dic` is a dictionary of `DataFrame`s for each DDL
category appearing in the definition. `implicits`
is a list of `category.column` names that should not be
printed. No underscore appears before the category
name.
"""
show_one_def(io,def_name,info_dic;implicits=[],ordering=ddlm_cat_order) = begin
    write(io,"\nsave_$def_name\n\n")
    # cats in ordering are dealt with first
    # append!(ordering,keys(info_dic))
    for cat in unique(Iterators.flatten((ordering,keys(info_dic))))
        if !haskey(info_dic,cat) continue end
        df = info_dic[cat]
        if nrow(df) == 0 continue end
        out_order = get(ddlm_def_order,cat,())
        if nrow(df) == 1 show_set(io,cat,df,implicits=implicits,indents=[4,33],order=out_order) end
        if nrow(df) > 1 show_loop(io,String(cat),df,implicits=implicits,indents=[4,33],order=out_order) end
    end
    write(io,"\nsave_\n")
end

# We can skip defaults

"""
    show_set(io,cat,df;implicits=[],indents=[0,30],order=[])

Format the contents of single-row DataFrame `df` as a series
of key-value pairs in CIF syntax. Anything in `implicits` is
ignored. `indents` gives indentation for the data name, and
then for the value, if that value would fit on a single line.
Items in the category are listed in the order they appear 
in `order`, and then the remainder are output in alphabetical
order.
"""
show_set(io,cat,df;implicits=[],indents=[0,30],order=()) = begin
    colnames = sort!(setdiff(propertynames(df),order))
    leftindent = " "^indents[1]
    valindent = indents[2]-1-indents[1] #always add a space
    for cl in Iterators.flatten((order,colnames))
        if cl in [:master_id,:__blockname,:__object_id] continue end
        if "$cat.$(String(cl))" in implicits continue end
        this_val = df[!,cl][]
        if ismissing(this_val) continue end
        if cat != :type && haskey(ddlm_defaults,(cat,cl)) && ddlm_defaults[(cat,cl)] == this_val continue end
        fullname = "_$cat.$cl"
        write(io,leftindent)
        write(io,fullname)
        padding = " "^(max(0,valindent-length(fullname)))
        write(io,padding*" ")
        write(io,format_for_cif(this_val)*"\n")
    end
end

"""
    show_loop(io,cat,df;implicits=[],indents=[0])

Format the contents of multi-row DataFrame `df` as a CIF loop.
 If `cat.col` appears in `implicits` then `col` is not output.
`indent` supplies the indents used for key-value pairs to aid
alignment. Fields are output in the order given by `order`,
then the remaining fields in alphabetical order.
"""
show_loop(io,cat,df;implicits=[],indents=[0,33],order=()) = begin
    if nrow(df) == 0 return end
    rej_names = filter(x->split(x,".")[1]==cat,implicits)
    rej_names = map(x->split(x,".")[2],rej_names)
    append!(rej_names,["master_id","__blockname","__object_id"])
    imp_reg = Regex("$(join(rej_names,"|^"))")
    write(io,format_for_cif(df[!,Not(imp_reg)];catname=cat,indent=indents,order=order))
end       

"""
    show(io::IO,::MIME"text/cif",c::Cif)

Write the contents of `c` as a CIF file to `io`.
"""
show(io::IO,::MIME"text/cif",c::Cif) = begin
    for k in keys(c)
        write(io,"data_$k\n")
        show(io,MIME("text/cif"),c[k])
    end
end

Base.show(io::IO,::MIME"text/cif",c::CifContainer) = begin
    write(io,"\n")
    key_vals = setdiff(collect(keys(c)),get_loop_names(c)...)
    for k in key_vals
        item = format_for_cif(first(c[k]))
        write(io,"$k\t$item\n")
    end
    
    # now go through the loops
    for one_loop in get_loop_names(c)
        a_loop = get_loop(c,first(one_loop))
        write(io,format_for_cif(a_loop))
    end
end

Base.show(io::IO,::MIME"text/cif",b::NestedCifContainer) = begin
    # first output the save frames
    show(io,MIME("text/cif"),get_frames(b))
    show(io,MIME("text/cif"),Block(b))
end

centered_header(header_text;width=78) = begin
    lines = split(header_text,"\n")
    outstring = "#"^78*"\n"*"#"*' '^76*"#\n"
    first_line = true
    for one_line in lines
        if length(one_line) > width-4 one_line = one_line[1:(width-4)] end
        if first_line
            padding_l = ' '^round(Int,(width-2 - length(one_line))/2)
            padding_r = ' '^(width-2-length(padding_l)-length(one_line))
            first_line = false
        else
            padding_l = "  "
            padding_r = ' '^(width-4-length(one_line))
        end
        outstring *= '#'*padding_l*one_line*padding_r*"#\n#"*' '^(width-2)*"#\n"
    end
    return outstring*"#"^78*"\n\n"
end

"""
    show(io::IO,MIME(text/cif),ddlm_dic::DDLm_Dictionary;header="")

Output `ddlm_dic` in CIF format. `header` can contain text that will
be output in a comment box at the top of the file. Lines may be no
longer than 74 characters. Multiple lines are will be separated by spaces.
"""
show(io::IO,::MIME"text/cif",ddlm_dic::DDLm_Dictionary;header="") = begin
    dicname = ddlm_dic[:dictionary].title[]
    write(io,"#\\#CIF_2.0\n")
    # center header text
    write(io,centered_header(header))
    write(io,"data_$(uppercase(dicname))\n\n")
    top_level = ddlm_dic[:dictionary]
    show_set(io,"dictionary",top_level,indents=[4,33])
    # And the unlooped top-level stuff
    top_level = ddlm_dic[dicname]
    for c in keys(top_level)
        if c == :dictionary continue end
        if nrow(top_level[c]) == 1
            show_set(io,String(c),top_level[c],indents=[4,33])
        end
    end
    # Now for the rest
    head = find_head_category(ddlm_dic)
    show_one_def(io,uppercase(head),ddlm_dic[head])
    all_cats = sort!(get_categories(ddlm_dic))
    for one_cat in all_cats
        if one_cat == head continue end
        cat_info = ddlm_dic[one_cat]
        show_one_def(io,uppercase(one_cat),cat_info)
        items = sort(get_names_in_cat(ddlm_dic,one_cat))
        for one_item in items
            show_one_def(io,one_item,ddlm_dic[one_item])
        end
    end
    # And the looped top-level stuff
    top_level = ddlm_dic[dicname]
    for c in keys(top_level)
        if c == :dictionary continue end
        if nrow(top_level[c]) > 1
            show_loop(io,String(c),top_level[c])
        end
    end
end

     
#
# **Output**
#
# DDL2 makes use of implicit values based on the block name. We
# ignore any columns contained in the 'implicit' const.
#

"""
    show(io::IO,::MIME"text/cif",ddl2_dic::DDL2_Dictionary)

Output `ddl2_dic` in CIF format.
"""
show(io::IO,::MIME"text/cif",ddl2_dic::DDL2_Dictionary) = begin
    dicname = ddl2_dic[:dictionary].title[]
    write(io,"#")
    write(io,"""
##############################################################
#
#        $dicname (DDL2)
#
##############################################################\n""")
    write(io,"data_$dicname\n")
    implicit_info = get_implicit_list()
    top_level = ddl2_dic[:datablock]
    show_set(io,"datablock",top_level,implicits=implicit_info)
    top_level = ddl2_dic[:dictionary]
    show_set(io,"dictionary",top_level,implicits=implicit_info)
    # Now for the rest
    all_cats = sort(get_categories(ddl2_dic))
    for one_cat in all_cats
        cat_info = ddl2_dic[one_cat]
        show_one_def(io,one_cat,cat_info,implicits=implicit_info)
        items = sort(get_names_in_cat(ddl2_dic,one_cat))
        for one_item in items
            show_one_def(io,one_item,ddl2_dic[one_item],implicits=implicit_info)
        end
    end
    # And the looped top-level stuff
    for c in [:item_units_conversion,:item_units_list,:item_type_list,:dictionary_history,
              :sub_category,:category_group_list]
        if c in keys(ddl2_dic.block) && nrow(ddl2_dic[c]) > 0
            show_loop(io,String(c),ddl2_dic[c],implicits=implicit_info)
        end
    end
end
