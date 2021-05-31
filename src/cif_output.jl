# **Routines for outputting CIF values

export format_for_cif
export line_length
export text_indent
export text_prefix
export value_col
export value_indent
export loop_indent
export loop_align
export loop_step
export min_whitespace
export which_delimiter #for use in checkers

# The magic constants for formatting
const line_length = 80
const text_indent = 4
const text_prefix = ">"
const value_col = 33
const loop_indent = 2
const value_indent = text_indent + loop_indent
const loop_align = 10
const loop_step = 5
const min_whitespace = 2

"""
    which_delimiter(value)

Return the appropriate delimiter to use for `value` and which style rule that 
delimiter is chosen by.
"""
which_delimiter(value::AbstractString) = begin
    if length(value) == 0 return ("'","2.1.2") end
    if occursin("\n", value) return ("\n;","2.1.7") end
    if occursin("'''",value) && occursin("\"\"\"",value) return ("\n;","2.1.6") end
    if occursin("'''",value) return ("\"\"\"","2.1.5") end
    if occursin("'",value) && occursin("\"",value) return ("'''","2.1.4") end
    if occursin("'",value) return ("\"","2.1.3") end
    q = match(r"^data|^save|^global|^loop"i,String(value))
    if !isnothing(q) return ("'","2.1.2") end
    if first(value) in ['_','[','{'] return ("'","2.1.2") end
    q = match(r"\S+",String(value))
    if !isnothing(q) && q.match == value return ("","2.1.1") end
    return ("'","2.1.2")
end

which_delimiter(value) = ("","CIF")

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
    format_for_cif(val::AbstractString;delim=nothing,cif1=false)

Return `val` formatted as a text string for output in
a CIF2 file.  Line folding and prefixing is not used.

If `cif1`, triple-quoted strings
will never be output, but output will fail if the
supplied string contains the "\n;" digraph.  For `cif1`,
non-ASCII code points in `val` are output despite
this being a violation of the CIF1 standard.

If `pretty`, semicolon-delimited strings will be indented
by `text_indent` spaces.
"""
format_for_cif(val::AbstractString;delim=nothing,pretty=false,cif1=false,kwargs...) = begin
    if delim === nothing
        delim,_ = which_delimiter(val)
    end
    if delim == "\n;" && occursin("\n;",val) && cif1
        throw(error("$val cannot be formatted using CIF1 syntax"))
    end
    if delim == "\n;" && pretty
        return format_cif_text_string(val)
    else
        return delim*val*delim
    end
end

format_for_cif(val::Real;kwargs...) = begin
    return "$val"
end

format_for_cif(val::Missing;kwargs...) = "?"
format_for_cif(val::Nothing;kwargs...) = "."

format_for_cif(val::Array;indent=value_indent,max_length=line_length,level=1,kwargs...) = begin
    outstring = IOBuffer()
    if level > 2
        write(outstring,"\n"*' '^(value_indent + 2*level))
    end
    write(outstring,"[")
    line_pos = 1
    for (i,item) in enumerate(val)
        value = format_for_cif(item;level=level+1,kwargs)
        if '\n' in value
            line_pos = length(value) - findlast(isequal('\n'),value)
            write(outstring, value)
        else
            if length(value) + line_pos + 1 > max_length
                write(outstring,"\n")
                write(outstring,' '^(value_indent+2*level)*value)
                line_pos = length(value)+value_indent + 2*level
            else
                if i > 1  #not the first value
                    write(outstring, ' '^min_whitespace)
                    line_pos = line_pos + length(value) + min_whitespace
                else
                    line_pos = line_pos + length(value)
                end
                write(outstring,value)
            end
        end
    end
    if level > 2
        write(outstring,"\n"*' '^(value_indent + 2*level))
    end
    return String(take!(outstring))*']'
end

format_for_cif(val::Dict;indent=value_indent,max_length=line_length,level=1,kwargs...) = begin
    outstring = IOBuffer()
    write(outstring,"{")
    line_pos = 1
    for (k,v) in val
        mini_val = "\"$k\":$(format_for_cif(v)) "
        if '\n' in mini_val
            line_pos = length(mini_val) - findlast(isequal('\n'),mini_val)
            write(outstring, mini_val)
        else
            if length(mini_val) + line_pos + 1 > line_length
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
    format_cif_text_string(value,indent=text_indent,width=line_length,justify=false)

Format string `value` as a CIF semicolon-delimited string,
inserting `indent` characters at the beginning of each line and
with no lines greater than `line_length`, removing trailing space. If
`justify` is true, each line will be filled as close as possible
to the maximum length, which could potentially spoil formatting like
centering or ASCII equations.
"""
format_cif_text_string(value;indent=text_indent,width=line_length,justify=false) = begin
    if occursin("\n",value)
        lines = split(value,"\n")
    else
        lines = [value]
    end
    reflowed = []
    remainder = ""
    # remove empty lines at top
    while strip(lines[1]) == "" lines = lines[2:end] end
    # remove empty lines at bottom
    while strip(lines[end]) == "" pop!(lines) end
    # find minimum current indent
    have_indent = filter(x->match(r"\S+",x)!== nothing,lines)
    old_indent = min(map(x->length(match(r"^\s*",x).match),have_indent)...)
    if justify   # all one line
        t = map(lines) do x
            if match(r"\S+",x) !== nothing x[old_indent+1:end]
            else
                x
            end
        end
        lines = [" "^old_indent*join(t," ")]    #one long line
    end
    for l in lines
        sl = strip(l)
        if length(sl) == 0
            if remainder != ""
                push!(reflowed, " "^text_indent*remainder*"\n")
            end
            push!(reflowed,"")
            remainder=""
            continue
        end
        # remove old indent, add new one
        longer_line = " "^text_indent*(remainder=="" ? "" : remainder*" ")*rstrip(l)[old_indent+1:end]
        remainder, final = reduce_line(longer_line,width)
        push!(reflowed,final)
    end
    while remainder != ""
        remainder,final = reduce_line(" "^text_indent*remainder,width)
        push!(reflowed,final)
    end
    return "\n;\n"*join(reflowed,"\n")*"\n;"
end

"""
    reduce_line(line,max_length)

Return a line with words over the limit removed, unless there
is no whitespace, in which case nothing is done.
"""
reduce_line(line,max_length) = begin
    if length(line) < max_length return "",line end
    cut = length(line)
    while cut > line_length && cut != nothing
        cut = findprev(' ',line,cut-1)
    end
    if cut === nothing return "",line end
    return line[cut+1:end],line[1:cut-1]
end

"""
If passed a DataFrame we format a loop. If passed an additional name for
the category, each column name is prefixed by this name. `indent` contains
the indent for the loop list and the indent for key-value items, where
the latter is used when there is only one item in the loop and it would
fit in an 80-character line. Columns are output in `order`, and then
alphabetical order for anything not in `order`. If `pretty` is true, 
multi-line data values have line-breaks and spaces inserted to create a
pleasing layout.
"""
format_for_cif(df::DataFrame;catname=nothing,indent=[text_indent,value_col],
               order=(),pretty=false) = begin
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
    dname_indent = indent[1]+loop_indent
    for n in final_list
        write(outstring," "^dname_indent*outname*String(n)*"\n")
    end
    stringified,widths = prepare_for_layout(select(df,final_list...),pretty=pretty)
    starts,lines = calc_ideal_spacing(widths)

    println("Starting columns: $starts/$lines")
    for one_row in eachrow(stringified)
        line_pos = 0
        for (n,name) in enumerate(final_list)
            new_val = getproperty(one_row,name)
            if line_pos == 0    # start of line
                write(outstring,' '^(starts[n]-line_pos))
                write(outstring,new_val)
                line_pos = starts[n] + layout_length(new_val)
            else
                if starts[n] <= starts[n-1] || lines[n] > lines[n-1]    # new line
                    if new_val[1] != '\n'
                        write(outstring,"\n")
                    end
                    line_pos = 0
                end
                if new_val[1] != '\n'
                    write(outstring,' '^(starts[n]-line_pos))
                end
                write(outstring,new_val)
                line_pos = starts[n] + layout_length(new_val)
            end
        end
        write(outstring,"\n")
    end
    return String(take!(outstring))
end

layout_length(x) = begin
    if occursin("\n",x) line_length else length(x) end
end

layout_length(x::Union{Array,Dict}) = begin
    layout_length(format_for_cif(x))
end

layout_length(x::Union{Missing,Nothing}) = 1
layout_length(x::Number) = length("$x")

"""
    find_best_delimiter(a)

Find the delimiter most suited for all values in `a`, assuming
that line breaks are inserted for values longer than `line_length`
"""
find_best_delimiter(a;max_length=line_length) = begin
    prec = ("\n;","\"\"\"","'''","\"","'","")
    prelim = unique([which_delimiter(x)[1] for x in a])
    if length(prelim) > 1
        delim = prec[findfirst(x->x in prelim,prec)]
        if delim == "\"\"\""
            if any(x->occursin(delim,x),a) delim = "\n;" end
        elseif delim == "\""
            if any(x->occursin(delim,x),a) delim = "'''" end
        end
    else
        delim = prelim[]
    end
    # Now adjust for line length
    width = 2*length(delim) + maximum(layout_length.(a))
    if width > max_length 
        delim = "\n;"
    end
    return delim
end

# Find the best delimiters for data frame. Some columns may be promoted to
# semicolon-delimited as they will take up more than the required length
find_best_delimiters(d::DataFrame) = begin
    delims = String[]
    for (i,col) in enumerate(eachcol(d))
        if i == 2 && ncol(d) == 2
            push!(delims,find_best_delimiter(col,max_length=line_length-loop_align-text_indent))
        elseif i > 1
            push!(delims,find_best_delimiter(col,max_length=line_length-loop_step))
        else
            push!(delims,find_best_delimiter(col,max_length=line_length-loop_align))
        end
    end
    return delims 
end

"""
    prepare_for_layout(df)

Calculate the appropriate delimiter for each column in `df`. If
`pretty` is true, insert spaces and line breaks in multi-line 
data names to look pleasing.
"""
prepare_for_layout(df;pretty=false) = begin
        
    delims = find_best_delimiters(df)
    stringified = map(x->format_for_cif.(x[2],delim=x[1],pretty=pretty), zip(delims,eachcol(df)))
    stringified = DataFrame(stringified,names(df),copycols=false)
    lengths = mapcols(x->maximum(layout_length.(x)),stringified)
    widths = map(zip(delims,eachcol(lengths))) do d
        if d[1] == "\n;" line_length
        else d[2][]+2*(length(d[1]))
        end
    end
    return stringified,widths
end

"""
    calc_ideal_spacing(colwidths)

Calculate column start positions based on reported widths. Packets start at loop_align, with
subsequent values aligned to loop align
"""
calc_ideal_spacing(colwidths) = begin
    calc_starts = []
    calc_lines = []
    old_p = 1
    line = 1
    sumsofar = 0
    interim = []
    
    start_line() = begin
        if length(colwidths) == 2 && length(calc_starts) == 1
            indent = loop_align + text_indent
        else
            indent = loop_step
        end
        interim = [indent]   #exception for 2-value packets
        calc_col = length(calc_starts)+1
        if calc_col > length(colwidths) return end
        println("Starting line, column $calc_col")
        if colwidths[calc_col] + indent > line_length
            finish_line()
            interim = []
        else
            sumsofar = indent + colwidths[calc_col]
            println("After starting line next col is $sumsofar")
        end 
    end
    
    finish_line() = begin
        if length(interim) ==1
            push!(calc_starts,interim[])
            push!(calc_lines,line)
            sumsofar = 0
            line = line + 1
            return
        end
        final_col = length(calc_starts) + length(interim)
        final_pos = interim[end] + colwidths[final_col]
        println("Final width $final_pos")
        println("$interim , $calc_starts")
        remainder = floor(Int64,(line_length - final_pos)/(length(interim)-1))
        if remainder < 0
            throw(error("Line overflow!"))
        end
        push!(calc_starts,interim[1])
        append!(calc_starts,interim[2:end] .+ remainder)
        # adjust for two value rule
        println("After remainder $interim $calc_starts")
        if length(interim) == 2 && interim[2] < value_col && calc_starts[end] > value_col
            println("Two value rule engaged")
            calc_starts[end] = value_col
        end
        append!(calc_lines,fill(line,length(interim)))
        line = line + 1
        sumsofar = 0
    end
    
    for p in 1:length(colwidths)
        if length(interim) == 0   #start of line
            start_line()
            continue
        end
        println("Col $p: $sumsofar")
        if sumsofar + 2 + colwidths[p] < line_length
            push!(interim,sumsofar)
            sumsofar += colwidths[p] + 2
            println("Interim $interim")
            continue
        end
        finish_line()
        start_line()
    end
    if length(interim) > 0
        println("Leftover: $interim")
        finish_line()
    end
    return (calc_starts,calc_lines)
end

# Default order for outputting DDLm categories
const ddlm_cat_order = (:definition,:alias,:description,:name,:type,:import,:description_example)
const ddlm_def_order = Dict(:definition=>(:id,:scope),:type=>(:purpose,:source),
                            :name => (:category_id,:object_id),
                            :enumeration_set => (:state,:detail),
                            :dictionary_valid=>(:application,:attributes),
                            :dictionary_audit=>(:version,:date,:revision)
                            )
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
        if nrow(df) == 1 show_set(io,cat,df,implicits=implicits,order=out_order,reflow=true) end
        if nrow(df) > 1 show_loop(io,String(cat),df,implicits=implicits,order=out_order,reflow=true) end
    end
    write(io,"\nsave_\n")
end

# We can skip defaults

"""
    show_set(io,cat,df;implicits=[],indents=[0,30],order=[])

Format the contents of single-row DataFrame `df` as a series
of key-value pairs in CIF syntax. Anything in `implicits` is
ignored. `indents` gives number of spaces before the data name, and
then the column for the value, if that value would fit on a single line.
Items in the category are listed in the order they appear 
in `order`, and then the remainder are output in alphabetical
order. If `reflow` is true, data values may have newlines and
    whitespace inserted during formatting.
"""
show_set(io,cat,df;implicits=[],indents=[text_indent,value_col],order=(),
         reflow=false) = begin
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
        next_pos = indents[1] + length(fullname) + min_whitespace
        if next_pos < indents[2] next_pos = indents[2] end
        val_as_string = format_for_cif(this_val)
        if occursin("\n",val_as_string)
            if val_as_string[1] == '\n'
                write(io,val_as_string*"\n")
            else
                write(io,"\n"*" "^value_indent*val_as_string*"\n")
            end
        elseif length(val_as_string) < line_length - next_pos  
            padding = " "^(next_pos - indents[1] - length(fullname))
            write(io,padding*" ")
            write(io,val_as_string*"\n")
        elseif length(val_as_string) < line_length - value_indent || !reflow
            write(io,"\n"*" "^value_indent*val_as_string*"\n")
        else
            write(io,format_cif_text_string(this_val)*"\n")
        end
    end
end

"""
    show_loop(io,cat,df;implicits=[],indents=[0],reflow=false)

Format the contents of multi-row DataFrame `df` as a CIF loop.
 If `cat.col` appears in `implicits` then `col` is not output.
`indent` supplies the indents used for key-value pairs to aid
alignment. Fields are output in the order given by `order`,
then the remaining fields in alphabetical order. If `reflow`
is true, multi-line data values will have spaces and line feeds
inserted to create a pleasing layout.
"""
show_loop(io,cat,df;implicits=[],indents=[loop_indent,value_col],order=(),
          reflow=false) = begin
     if nrow(df) == 0 return end
              rej_names = filter(x->split(x,".")[1]==cat,implicits)
              rej_names = map(x->split(x,".")[2],rej_names)
              append!(rej_names,["master_id","__blockname","__object_id"])
              imp_reg = Regex("$(join(rej_names,"|^"))")
              write(io,format_for_cif(df[!,Not(imp_reg)];catname=cat,indent=indents,order=order,
                                      pretty=reflow))
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

const ddlm_toplevel_order = (:dictionary_valid,:dictionary_audit)
"""
    show(io::IO,MIME("text/cif"),ddlm_dic::DDLm_Dictionary;header="")

Output `ddlm_dic` in CIF format. `header` contains text that will
be output in a comment box at the top of the file, which will replace
any header comment stored in `ddlm_dic`.
"""
show(io::IO,::MIME"text/cif",ddlm_dic::DDLm_Dictionary;header="") = begin
    dicname = ddlm_dic[:dictionary].title[]
    #
    # Header
    #
    write(io,"#\\#CIF_2.0\n")
    if header != ""
        # center header text
        write(io,centered_header(header))
    elseif ddlm_dic.header_comments != ""
        write(io,replace(ddlm_dic.header_comments,r"^"m => "#"))
    end
    #
    # Top level
    #
    implicits = get_implicit_list(ddlm_dic)
    write(io,"\ndata_$(uppercase(dicname))\n\n")
    top_level = ddlm_dic[:dictionary]
    show_set(io,"dictionary",top_level,indents=[4,33],reflow=true)
    # And the unlooped top-level stuff
    top_level = ddlm_dic[dicname]
    for c in keys(top_level)
        if c == :dictionary continue end
        if nrow(top_level[c]) == 1
            show_set(io,String(c),top_level[c],reflow=true)
        end
    end
    #
    # Head category
    #
    head = find_head_category(ddlm_dic)
    show_one_def(io,uppercase(head),ddlm_dic[head])
    #
    # All categories
    #
    all_cats = sort!(get_categories(ddlm_dic))
    for one_cat in all_cats
        if one_cat == head continue end
        cat_info = ddlm_dic[one_cat]
        # Remove "master_id" as an explicit key
        ck = cat_info[:category_key]
        if nrow(ck) > 0
            ck = filter(row -> !occursin("master_id",row.name),ck)
            cat_info[:category_key] = ck
        end
        println("Output definition for $one_cat")
        show_one_def(io,uppercase(one_cat),cat_info)
        #
        #  Definitions in the categories
        #
        items = sort(get_names_in_cat(ddlm_dic,one_cat))
        for one_item in items
            if ddlm_dic[one_item][:name].object_id[] == "master_id" continue end
            println("Output definition for $one_item")
            show_one_def(io,one_item[2:end],ddlm_dic[one_item]) # no underscore
        end
    end
    #
    # And the looped top-level stuff at the end
    #
    top_level = ddlm_dic[dicname]
    for c in ddlm_toplevel_order
        if !(c in keys(top_level)) continue end
        if c == :dictionary continue end
        if nrow(top_level[c]) > 1
            show_loop(io,String(c),top_level[c],order=get(ddlm_def_order,c,()),reflow=true)
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
    implicit_info = get_implicit_list(ddl2_dic)
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
