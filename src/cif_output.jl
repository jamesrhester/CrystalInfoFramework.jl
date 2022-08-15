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
export calc_ideal_spacing #for use in checkers
export find_best_delimiters #for use in checkers
export ddlm_attribute_order #for use in checkers
export ddlm_toplevel_order

# The magic constants for formatting
const line_length = 80
const text_indent = 4
const text_prefix = ">"
const value_col = 35
const loop_indent = 2
const loop_align = 10
const loop_step = 5
const min_whitespace = 2
const value_indent = text_indent + loop_step

"""
    which_delimiter(value)

Return the appropriate delimiter to use for `value` and which style rule that 
delimiter is chosen by. Note that internal double and single quotes are
still allowed in CIF2.
"""
which_delimiter(value::AbstractString) = begin
    # deal with simple ones first
    if length(value) == 0 return ("'","2.1.2") end
    if occursin("\n", value) return ("\n;","2.1.3") end
    needs_delimiter = match(r"[][{}]",String(value)) !== nothing ||
        value[1] in ['\'','"','_',';','$','#']
    needs_delimiter = needs_delimiter || match(r"\s",String(value)) !== nothing
    needs_delimiter = needs_delimiter ||
        match(r"^data_|^save_|^global_|^loop_"i,String(value)) !== nothing
    if !needs_delimiter return ("","2.1.1") end
    # now choose the right one
    if occursin("'''",value) && occursin("\"\"\"",value) return ("\n;","2.1.2") end
    if occursin("'''",value)
        if occursin("\"",value)
            return ("\"\"\"","2.1.2")
        else
            return ("\"","2.1.2")
        end
    end
    if occursin("\"\"\"",value)
        if occursin("'",value)
            return ("'''")
        else
            return ("'")
        end
    end
    if occursin("'",value) && occursin("\"",value) return ("'''","2.1.2") end
    if occursin("'",value) return ("\"","2.1.2") end
    if occursin("\"",value) return ("'","2.1.2") end
    return ("'","2.1.2")
end

which_delimiter(value::Array) = ("[","CIF")
which_delimiter(value::Dict) = ("{","CIF")

which_delimiter(value) = ("","CIF")

which_prefix(value) = ("","CIF")

which_prefix(value::AbstractString) = begin
    if occursin("\n;", value) return (">","2.1.8") end
    return ("","CIF")
end

which_prefix(lines::Array) = begin
    bad = filter(x->length(x)>1 && x[1]==';',lines)
    if length(bad) > 0 return (">","2.1.8") end
    return ("","CIF")
end

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
    format_for_cif(val::AbstractString;delim=nothing,cif1=false,pretty=false,loop=false)

Return `val` formatted as a text string for output in
a CIF2 file.  Line folding is not used.

If `cif1`, triple-quoted strings
will never be output, but output will fail if the
supplied string contains the "\n;" digraph.  For `cif1`,
non-ASCII code points in `val` are output despite
this being a violation of the CIF1 standard.

If `pretty`, permission is granted to remove and insert whitespace
in multi-line strings to produce nicely spaced and indented text,
including removal of leading and trailing whitespace, which may
result in a single-line data value.

If `loop`, multi-line values should be indented for presentation in a loop,
if `pretty` is true.

As a simple heuristic, the string is assumed to be pre-formatted if at least
one line contains a sequence of 5 '#' characters.
"""
format_for_cif(val::AbstractString;delim=nothing,pretty=false,cif1=false,loop=false,kwargs...) = begin
    tgtval = val
    if delim === nothing
        # Figure out the best delimiter
        if pretty
            tgtval = strip(val)
        end
        delim,_ = which_delimiter(tgtval)
        if delim == "\n;" && pretty   #Stripping didn't simplify
            tgtval = strip(val,'\n')
        end
    end
    prefix,_ = which_prefix(tgtval)
    if delim == "\n;" && occursin("\n;",tgtval) && cif1
        throw(error("$val cannot be formatted using CIF1 syntax"))
    end
    if delim == "\n;"
        
        is_preformat = match(r"#####",tgtval) != nothing
        if pretty && !is_preformat  #
            if loop == :short indent = loop_align - 1
            elseif loop == :long indent = text_indent + loop_indent + 1
            else indent = text_indent
            end
            return format_cif_text_string(tgtval,indent;prefix=prefix,kwargs...)
        elseif prefix != ""
            return delim*apply_prefix_protocol(tgtval,prefix=prefix)*delim
        end
        @debug "Not pretty for $tgtval"
    end
    return delim*tgtval*delim
end

format_for_cif(val::Real;dummy=0,kwargs...) = begin
    return "$val"
end

format_for_cif(val::Missing;kwargs...) = "?"
format_for_cif(val::Nothing;kwargs...) = "."

"""
    format_for_cif(val::Array;indent=value_col,max_length=line_length,level=1,
                              ideal=false,kwargs...)

Format an array for output in a  CIF file, with maximum line length `line_length` and
current indentation level in compound object `level`. `indent` is the character position
of the opening delimiter, below which subsequent values are aligned if necessary. If
`ideal` is true, an error is raised if a smaller indent would improve the layout. 
"""
format_for_cif(val::Union{Array,Dict};indent=value_col,level=1,kwargs...) = begin
    result = ""
    try
        result = format_compound(val;ideal=true,indent=indent,level=level,kwargs...)
    catch e
        if level > 1
            @debug "At level $level, going up..."
            rethrow(e)
        end
        @debug "Level $level, got $e: trying smaller indent"
        result = format_compound(val;ideal=false,indent=value_indent,level=level,kwargs...)
    end
    return result
end
                              
format_compound(val::Array;indent=value_col,max_length=line_length,level=1,ideal=false,kwargs...) = begin
    outstring = IOBuffer()
    @debug "Format array" indent level ideal
    if level > 2
        write(outstring,"\n"*' '^(indent + level))
    end
    line_pos = indent + level - 1
    did_new_line = false
    close_new_line = false               
    for (i,item) in enumerate(val)
        value = format_for_cif(item;level=level+1,max_length=max_length,indent=indent,ideal=ideal)
        if '\n' in value
            line_pos = length(value) - findlast(isequal('\n'),value)
            write(outstring, value)
        else
            # We need to count the closing bracket if the whole value is on a
            # single line
            need_new_line = false
            final_bracket = i == length(val) && !did_new_line ? 1 : 0 
            if i == 1
                need_new_line = length(value) + line_pos + final_bracket > max_length
                close_new_line = (typeof(item) <: Dict || typeof(item) <: Array) && need_new_line
            elseif i > 1 && i < length(val)
                need_new_line = length(value) + line_pos + min_whitespace > max_length
            else # end
                need_new_line = length(value) + line_pos + min_whitespace + final_bracket > max_length
                close_new_line = (typeof(item) <: Dict || typeof(item) <: Array) || close_new_line
            end
            if ideal && level > 1 && need_new_line
                throw(error("Pos $line_pos, value $value, choose a better indent"))
            end
            if need_new_line
                write(outstring,"\n")
                this_indent = indent+level
                write(outstring,' '^(this_indent-1)*value)
                line_pos = length(value)+ this_indent - 1
                did_new_line = true
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
    if level > 2 || close_new_line
        write(outstring,"\n"*' '^(indent-1  + level - 1))
    end
    write(outstring,']')
    if level > 2 || close_new_line               
        return "[\n"*' '^(indent-1 + level)*String(take!(outstring))
    else
        return "["*String(take!(outstring))
    end
end

# If `ideal` is true, raise an error if a smaller indent would improve the
# layout.
format_compound(val::Dict;indent=value_indent,max_length=line_length,level=1,ideal=false,kwargs...) = begin
                   outstring = IOBuffer()
    @debug "format dict:" indent level ideal
    write(outstring,"{")
    line_pos = indent
    key_order = sort(collect(keys(val)))
    for (cnt,k) in enumerate(key_order)
        v = val[k]
        mini_val = "'$k':$(format_for_cif(v))"
        need_space = cnt > 1 ? min_whitespace : 0
        if '\n' in mini_val
            line_pos = length(mini_val) - findlast(isequal('\n'),mini_val) + need_space
            write(outstring, ' '^need_space)
            write(outstring,mini_val)
        else
            if length(mini_val) + line_pos + 1 + need_space > line_length
                if ideal && level > 1
                    throw(error("Pos $line_pos, value $mini_val, choose a better indent"))
                end
                write(outstring,"\n")
                write(outstring," "^(indent+level-1)*mini_val)
                line_pos = length(mini_val)+indent+level-1
            else
                write(outstring, ' '^need_space)
                write(outstring, mini_val)
                line_pos = line_pos + length(mini_val)+ need_space
            end
        end
    end
    return String(take!(outstring))*'}'
end

"""
    format_cif_text_string(value,indent,width=line_length,prefix="",justify=false)

Format string `value` as a CIF semicolon-delimited string, adjusted
so that no lines are greater than `line_length`, and each line starts with
`indent` spaces.
If `justify` is true, each line will be filled as 
close as possible to the maximum length and all spaces replaced by 
a single space, which could potentially spoil formatting like centering, tabulation
or ASCII equations.
"""
format_cif_text_string(value::AbstractString,indent;width=line_length,justify=false,prefix="",kwargs...) = begin
    # catch pathological all whitespace values
    if match(r"^\s+$",value) !== nothing return "\n;$value\n;" end
    # catch empty string
    if value == "" return "''" end
    if occursin("\n",value)
        lines = split(value,"\n")
    else
        lines = [value]
    end
    reflowed = []
    remainder = ""
    while strip(lines[1]) == "" lines = lines[2:end] end
    # remove empty lines at bottom
    while strip(lines[end]) == "" pop!(lines) end
    # find minimum current indent
    have_indent = filter(x->match(r"\S+",x)!== nothing,lines)
    old_indent = min(map(x->length(match(r"^\s*",x).match),have_indent)...)
    # remove trailing whitespace
    lines = map(x->rstrip(x),lines)
    #
    if justify   # all one line
        #println("Request to justify:\n$value")
        t = map(lines) do x
            # remove all multi-spaces
            r = replace(strip(x),r"\s+"=>s" ")
        end
        # add on old indent as it is assumed present below
        lines = [" "^old_indent*join(t," ")]    #one long line
    end
    for l in lines
        sl = strip(l)
        if length(sl) == 0
            if remainder != ""
                push!(reflowed, " "^indent*remainder*"\n")
            end
            push!(reflowed,"")
            remainder=""
            continue
        end
        # remove old indent, add new one
        longer_line = " "^indent*(remainder=="" ? "" : remainder*" ")*rstrip(l)[old_indent+1:end]
        remainder, final = reduce_line(longer_line,width)
        #println("rem, final: '$remainder', '$final'")
        push!(reflowed,final)
    end
    while remainder != ""
        remainder,final = reduce_line(" "^indent*remainder,width)
        push!(reflowed,final)
    end
    # Now apply prefix
    prefix,_ = which_prefix(reflowed)
    assembled = join(reflowed,"\n"*prefix)
    if prefix == ""
        return "\n;\n"*assembled*"\n;"
    else
        return "\n;"*prefix*"\\\n"*prefix*assembled*"\n;"
    end
end

"""
    reduce_line(line,max_length)

Return a line with words over the limit removed, unless there
is no whitespace, in which case nothing is done. The returned
line has any final whitespace removed.
"""
reduce_line(line,max_length) = begin
    if length(line) <= max_length return "",line end
    cut = length(line)
    while cut > line_length && cut != nothing
        cut = findprev(' ',line,cut-1)
    end
    if cut === nothing return "",line end
    # if only spaces at beginning of line give up
    # otherwise risk eternal loop from the indent
    if strip(line[1:cut-1]) == ""
        return "",line[cut+1:end]
    end
    return line[cut+1:end],rstrip(line[1:cut-1])
end

# Insert a prefix or blank first line
apply_prefix_protocol(val::AbstractString;prefix="") = begin
    if prefix != ""
        return "$prefix\\\n$prefix"*replace(val, "\n"=>"\n$prefix")
    else return val
    end
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
               order=(),kwargs...) = begin
    outstring = IOBuffer()
    inpad = " "^indent[1]
    write(outstring,inpad*"loop_\n")
    outname = ""
    if catname != nothing
        outname = "_"*catname*"."
    end
    # remove missing columns
    order = intersect(order,propertynames(df))               
    colnames = setdiff(sort!(propertynames(df)),order)
    final_list = filter(collect(Iterators.flatten((order,colnames)))) do n
        !(all(x->ismissing(x),df[!,n]))
    end
    dname_indent = indent[1]+loop_indent
    for n in final_list
        write(outstring," "^dname_indent*outname*String(n)*"\n")
    end
    for_output = select(df,final_list...)
    width_ranges,delims = prepare_for_layout(for_output;indent=indent[2],kwargs...)
    starts,lines,widths = calc_ideal_spacing(width_ranges)

    #println("Widths, starts: $widths $starts")
    loop_flag = :long
    if length(final_list) == 2 && delims[2] == "\n;" loop_flag = :short end               
    for one_row in eachrow(for_output)
        line_pos = 1  #where the next character should go
        for (n,name) in enumerate(final_list)
            new_val = getproperty(one_row,name)
            delim = delims[n]
            out_val = format_for_cif(new_val;delim=delim,loop=loop_flag,indent=starts[n],kwargs...)
            if line_pos == 1    # start of line
                if out_val[1] != '\n' write(outstring,' '^(starts[n]-line_pos))
                    write(outstring,out_val)
                else
                    write(outstring,out_val[2:end]) #already on new line
                end
                line_pos = starts[n] + length(out_val)
            else
                if starts[n] <= starts[n-1]+2 || lines[n] > lines[n-1]    # new line
                    if out_val[1] != '\n'
                        write(outstring,"\n")
                    end
                    line_pos = 1
                end
                if out_val[1] != '\n'
                    write(outstring,' '^(starts[n]-line_pos))
                end
                write(outstring,out_val)
                line_pos = starts[n] + length(out_val)
            end
        end
        write(outstring,"\n")
    end
    return String(take!(outstring))
end

"""
    layout_length(x;level=1,delim="")

Return minimum and maximum possible widths for this value when
formatting. Min and max only have meaning for compound data
values, which may be split in different ways.
"""
layout_length(x::AbstractString;level=1,delim=nothing) = begin
    if occursin("\n",x) || delim == "\n;"
        return fill(line_length,2)
    end
    if delim == nothing delim = which_delimiter(x)[1] end
    return fill(length(x) + 2*length(delim),2)
end

# For a list or dictionary we require the shortest length that
# does not split an internal compound or primitive value.
layout_length(x::Array;level=1,kwargs...) = begin
    no_delimiters = layout_length.(x;level=level+1)
    maxlen = sum([x[2] for x in no_delimiters])+2level + min_whitespace*(length(x)-1)
    minlen = maximum([x[2] for x in no_delimiters])
    if length(x) == 1 return (minlen+2*level,maxlen) end
    return (minlen+level, maxlen)
end

layout_length(x::Dict;level=1,kwargs...) = begin
    max_len = 0
    min_len = 0
    for (k,v) in x
        min_l,max_l = layout_length(v;level=level+1)
        min_l += length(k)+3
        if min_l > min_len min_len = min_l end
        max_len += max_l + length(k)+3
    end
    min_len = min_len + (length(x) == 1 ? 2 : 1)
    max_len = max_len + (min_whitespace*(length(x)-1)) + 2
    #println("Layout length $min_len,$max_len for $x")
    return (min_len,max_len)
end


layout_length(x::Union{Missing,Nothing};kwargs...) = (1,1)
layout_length(x::Number;kwargs...) = fill(length("$x"),2)

"""
    find_best_delimiter(a)

Find the delimiter most suited for all values in `a`, assuming
that line breaks are inserted for values longer than `line_length`
"""
find_best_delimiter(a;max_length=line_length) = begin
    prec = ("\n;","\"\"\"","'''","\"","'","")
    prelim = unique([which_delimiter(x)[1] for x in a])
    if "[" in prelim || "{" in prelim return "" end
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
    width = maximum([x[1] for x in layout_length.(a,delim=delim)])
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
prepare_for_layout(df;kwargs...) = begin        
    delims = find_best_delimiters(df)
    lengths = map(zip(eachcol(df),delims)) do x
        y = layout_length.(x[1],delim=x[2])
        (lower=max([z[1] for z in y]...),upper=max([z[2] for z in y]...))
    end           
    #stringified = map(x->format_for_cif.(x[2];delim=x[1],kwargs...), zip(delims,eachcol(df)))
    #stringified = DataFrame(stringified,names(df),copycols=false)
    return lengths,delims
end

"""
    calc_ideal_spacing(colwidths)

Calculate column start positions based on reported widths. Packets start at loop_align, with
subsequent values aligned to loop align. Widths are (lower,upper) named tuples, where lower
is the minimum
possible width and upper is the maximum possible width.  These are only different for compound
data values.
"""
calc_ideal_spacing(colwidths) = begin
    calc_starts = Int[] #locked-in starting positions
    calc_lines = Int[]  #locked-in line numbers
    calc_widths = Int[] #locked-in widths
    old_p = 1
    line = 1
    sumsofar = 0     #Final column so far without extra whitespace
    interim = Int[]  #values that may require addition of preceding whitespace

    # When starting a line we calculate the indent and then see if the
    # next value would take up the whole line; if not we add it to the
    # current line, if it is compound we take as much as we can
    start_line() = begin
        calc_col = length(calc_starts)+1
        if length(colwidths) == 2 && calc_col == 2
            indent = loop_align + text_indent  #exception for 2-value packets
        else
            indent = loop_align
        end
        if calc_col > length(colwidths)
            @warn "calc_col > num of cols!"
            return
        end
        interim = [indent]
        #println("Starting line, column $calc_col")
        if colwidths[calc_col].lower + indent > line_length
            push!(calc_widths,line_length)
            finish_line()
            interim = []
        elseif colwidths[calc_col].upper + indent <= line_length
            sumsofar = indent + colwidths[calc_col].upper
            push!(calc_widths,colwidths[calc_col].upper)
        else
            push!(calc_widths,line_length - indent)
            finish_line()  #fill up as far as we can
            interim = []
            #println("After starting line next col is $sumsofar")
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
        #println("End of line: $calc_starts $interim $calc_widths")
        final_col = length(calc_starts) + length(interim)
        final_pos = interim[end] + calc_widths[final_col]
        #println("Final width $final_pos")
        #println("$interim , $calc_starts")
        remainder = floor(Int64,(line_length - final_pos)/(length(interim)-1))
        if remainder < 0
            throw(error("Line overflow!"))
        end
        #println("Remainder is $remainder")
        for i in 1:length(interim)
            push!(calc_starts,interim[i] + remainder*(i-1))
        end
        # adjust for two value rule
        #println("After remainder $interim $calc_starts")
        if length(interim) == 2 && interim[2] < value_col && calc_starts[end] > value_col
            #println("Two value rule engaged")
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
        #println("Col $p: $sumsofar")
        if sumsofar + 2 + colwidths[p].upper <= line_length
            push!(interim,sumsofar+2)
            sumsofar += colwidths[p].upper + 2
            push!(calc_widths,colwidths[p].upper)
            continue
        end
        if sumsofar + 2 + colwidths[p].lower <= line_length
            push!(interim,sumsofar+2)
            push!(calc_widths,line_length - sumsofar - 2)
            sumsofar = line_length
            continue
        end
        finish_line()
        start_line()
    end
    if length(interim) > 0
        #println("Leftover: $interim")
        finish_line()
    end
    return (calc_starts,calc_lines,calc_widths)
end

"""
    ddlm_attribute_order

The recommended order for presenting DDLm definitions. Appears as a tuple 
of (category => Tuple{object_id,...},...). Exported to allow checking 
software easy access.
"""
const ddlm_attribute_order = (:definition => (:id,:scope,:class),
                              :definition_replaced => (:id,:by),
                              :alias => (:definition_id,),
                              :definition => (:update,),
                              :description => (:text,),
                              :name => (:category_id,:object_id,:linked_item_id),
                              :category_key => (:name,),
                              :type => (:purpose,:source,:container,:dimension,:contents,
                                        :contents_referenced_id,
                                        :indices,:indices_referenced_id),
                         :enumeration => (:range,),
                         :enumeration_set => (:state,:detail),
                         :enumeration => (:default,),
                         :units => (:code,),
                         :description_example => (:case,:detail),
                         :import => (:get,),
                         :method => (:purpose,:expression)
                         )

const ddlm_no_justify = (:method,:description,:description_example) #do not reformat items in this category
const ddl2_no_justify = (:category,:category_examples,:item,:item_examples)
# Always use semicolon delimiters
const ddlm_semicolons = Dict(:description=>(:text,),:method=>(:expression,))
"""
    show_one_def(io,def_name,info_dic;implicits=[])

Convert one dictionary definition for `def_name` to text. 
`info_dic` is a dictionary of `DataFrame`s for each DDL
category appearing in the definition. `implicits`
is a list of `category.column` names that should not be
printed. No underscore appears before the category
name.
"""
show_one_def(io,def_name,info_dic;implicits=[],ordering=ddlm_attribute_order) = begin
    write(io,"\nsave_$def_name\n\n")
    blank_line = true  #if previous line was blank to avoid double blanks
    # cats in ordering are dealt with first
    # append!(ordering,keys(info_dic))
    if length(ordering) == 0
        ordering = []
        for (k,df) in info_dic
            push!(ordering,(k,setdiff(propertynames(df),(:master_id,:__blockname,:__object_id))))
        end
    end
    leftover = Dict()
    final_chance = Dict()
    for (k,df) in info_dic
        leftover[k] = propertynames(df)
        final_chance[k] = 0
    end
    for (k,_) in ordering
        haskey(final_chance,k) ? final_chance[k] = final_chance[k]+1 : 0
    end
    for chunk in ordering
        cat,objs = chunk
        if !haskey(info_dic,cat) continue end
        df = info_dic[cat]
        if nrow(df) == 0 continue end
        final_chance[cat] = final_chance[cat] - 1
        out_order = filter(x-> x in propertynames(df),objs)
        justify = !(cat in ddlm_no_justify) && !(cat in ddl2_no_justify)
        semis = get(ddlm_semicolons,cat,())
        if nrow(df) == 1
            if length(out_order) > 0
                if cat == :import && out_order == (:get,) && blank_line == false
                    write(io,"\n")
                end
                show_set(io,cat,df,implicits=implicits,order=out_order,reflow=true,justify=justify,semis=semis)
                if cat == :import && out_order == (:get,)
                    write(io,"\n")
                    blank_line = true
                else
                    blank_line = false
                end
                leftover[cat] = setdiff(leftover[cat],objs)
                if length(leftover[cat]) == 0 continue end
            end
            if final_chance[cat] == 0
                show_set(io,cat,df,implicits=implicits,order=sort(leftover[cat]),reflow=true,justify=justify,semis=semis)
            end
        end
        if nrow(df) > 1
            if !blank_line write(io,"\n") end
            show_loop(io,String(cat),df,implicits=implicits,order=out_order,reflow=true,justify=justify)
            write(io,"\n")
            blank_line = true
        end
    end
    if !blank_line write(io,"\n") end
    write(io,"save_\n")
end

# We can skip defaults

"""
    show_set(io,cat,df;implicits=[],indents=[0,30],order=[],reflow=false,
             justify=false,semis=())

Format the contents of single-row DataFrame `df` as a series
of key-value pairs in CIF syntax. Anything in `implicits` is
ignored. `indents` gives number of spaces before the data name, and
then the column for the value, if that value would fit on a single line.
Only items appearing in `order` are output, in the order they appear, unless
`order` is empty, in which case all items are output. If `reflow` is true, 
data values may have newlines and
whitespace inserted during formatting. If `justify` and
`reflow` are true, whitespace may also be removed. `semis` is a list
of column names for which semicolon delimiters must be used.
"""
show_set(io,cat,df;implicits=[],indents=[text_indent,value_col],order=(),
         reflow=false, justify=false,semis=()) = begin
    if nrow(df) > 1
        throw(error("Request to output multi-row dataframe for $cat as single row"))
    end
    pn = propertynames(df)
    colnames = length(order)>0 ? intersect(order,pn) : sort!(pn)
    leftindent = " "^indents[1]
    # Add any missing key columns         
    for cl in colnames
        if cl in [:master_id,:__blockname,:__object_id] continue end
        if "$cat.$(String(cl))" in implicits continue end
        this_val = df[!,cl][]
        if ismissing(this_val) continue end
        if haskey(ddlm_defaults,(cat,cl)) && ddlm_defaults[(cat,cl)] == this_val
            if !(cat == :type && cl in (:purpose,:source,:container,:contents)) &&
                !(cat == :method && cl == :purpose) continue
            end
        end
        fullname = "_$cat.$cl"
        write(io,leftindent)
        write(io,fullname)
        next_pos = indents[1] + length(fullname) + min_whitespace
        if next_pos < indents[2] next_pos = indents[2] end
        
        # Compound values may have internal newlines if they start at value_col,
        # so we check if the other indent fixes this

        if cl in semis delim="\n;" else delim = nothing end
        lwidth = layout_length(this_val,delim=delim)[1]
        if lwidth + next_pos - 1 <= line_length
            val_as_string = format_for_cif(this_val;indent=next_pos,pretty=reflow,justify=justify,delim=delim)
            padding = " "^(next_pos - indents[1] - length(fullname)-1)
            write(io,padding)
            write(io,val_as_string*"\n")
        else
            val_as_string = format_for_cif(this_val;indent=value_indent,pretty=reflow,justify=justify,delim=delim)
            if val_as_string[1] == '\n'
                write(io,val_as_string*"\n")
            elseif lwidth <= line_length - value_indent + 1 || !reflow
                write(io,"\n"*" "^(value_indent-1)*val_as_string*"\n")
            elseif this_val isa Vector || this_val isa Dict #already laid out for us
                write(io,"\n"*" "^(value_indent-1)*val_as_string*"\n")
            else
                write(io,format_cif_text_string(this_val,text_indent;pretty=reflow,justify=justify)*"\n")
            end
        end
    end
end

"""
    show_loop(io,cat,df;implicits=[],indents=[text_indent,value_col],reflow=false,justify=false)

Format the contents of multi-row DataFrame `df` as a CIF loop.
 If `cat.col` appears in `implicits` then `col` is not output.
`indent` supplies the indents used for key-value pairs to aid
alignment. Fields are output in the order given by `order`,
then the remaining fields in alphabetical order. If `reflow`
is true, multi-line data values will have spaces and line feeds
inserted to create a pleasing layout. If `justify` is true,
whitespace will be removed to fill lines completely.
"""
show_loop(io,cat,df;implicits=[],indents=[text_indent,value_col],order=(),
          reflow=false,justify=false) = begin
     if nrow(df) == 0 return end
              rej_names = filter(x->split(x,".")[1]==cat,implicits)
              rej_names = map(x->split(x,".")[2],rej_names)
              append!(rej_names,["master_id","__blockname","__object_id"])
              imp_reg = Regex("$(join(rej_names,"|^"))")
              write(io,format_for_cif(df[!,Not(imp_reg)];catname=cat,indent=indents,order=order,
                                      pretty=reflow,justify=justify))
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

Base.show(io::IO,::MIME"text/cif",c::CifContainer;ordering=[]) = begin
    write(io,"\n")
    key_vals = setdiff(collect(keys(c)),get_loop_names(c)...)
    for k in ordering
        if k in key_vals
            item = format_for_cif(first(c[k]))
            write(io,"$k\t$item\n")
        end
    end
    # now write out the rest
    for k in key_vals
        if !(k in ordering)
            item = format_for_cif(first(c[k]))
            write(io,"$k\t$item\n")
        end
    end
    # now go through the loops
    for one_loop in get_loop_names(c)
        a_loop = get_loop(c,first(one_loop))
        write(io,format_for_cif(a_loop,order=Symbol.(ordering)))
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
    ddlm_toplevel_order

The recommended order for presenting DDLm dictionary-level information in a DDL
dictionary file as a tuple of (category => Tuple{object_id,...},...). Exposed
to allow checking software easy access.
"""
const ddlm_toplevel_order = (:dictionary => (:title,:class,:version,:date,:uri,:ddl_conformance,
                                        :namespace),
                        :description => (:text,),
                        :dictionary_valid => (:scope,:option,:attributes),
                        :dictionary_audit => (:version,:date,:revision)
                        )

"""
    show(io::IOContext,MIME("text/cif"),ddlm_dic::DDLm_Dictionary;header="")

Output `ddlm_dic` in CIF format. `header` contains text that will
be output in a comment box at the top of the file, which will replace
any header comment stored in `ddlm_dic`.
"""
show(io::IOContext,::MIME"text/cif",ddlm_dic::DDLm_Dictionary;header="") = begin
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
    top_level = ddlm_dic[dicname]
    for (cat,objs) in ddlm_toplevel_order
        if !haskey(top_level,cat) continue end
        if nrow(top_level[cat]) > 1 break end
        show_set(io,String(cat),top_level[cat],indents=[text_indent,value_col],reflow=true,
                 order=objs)
    end
    for (c,frame) in top_level
        if c in (:dictionary,:description) continue end
        if nrow(frame) == 1
            show_set(io,String(c),frame,reflow=true)
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
    fcat,_ = get_dict_funcs(ddlm_dic)
    all_cats = get_sorted_cats(ddlm_dic,head)
    # Function category is at the end
    if !isnothing(fcat)
        deleteat!(all_cats,findfirst(isequal(fcat),all_cats))
        push!(all_cats,fcat)
    end
    for one_cat in all_cats
        if one_cat == head continue end
        cat_info = ddlm_dic[one_cat]
        # Remove "master_id" as an explicit key
        ck = cat_info[:category_key]
        if nrow(ck) > 0
            ck = filter(row -> !occursin("master_id",row.name),ck)
            cat_info[:category_key] = ck
        end
        @debug "Output definition for $one_cat"
        show_one_def(io,uppercase(one_cat),cat_info)
        #
        #  Definitions in the categories
        #
        items = sort_item_names(ddlm_dic,one_cat)
        for one_item in items
            one_def = ddlm_dic[one_item]
            @debug one_item
            if one_def[:name].object_id[] == "master_id" continue end
            show_one_def(io,one_item[2:end],one_def) # no underscore
        end
    end
    #
    # And the looped top-level stuff at the end
    #
    for (c,objs) in ddlm_toplevel_order
        if !(c in keys(top_level)) continue end
        if nrow(top_level[c]) > 1
            write(io,"\n")
            @debug "Formatting $c"
            show_loop(io,String(c),top_level[c],order=objs,reflow=true)
        end
    end
end

# Note that sometimes there will be categories that are not defined
# in the dictionary, as they are defined in an imported dictionary.
# We need to make sure we don't accidentally miss out on outputting
# them. We add them at the end until we have a standard for how they
# should be presented.
get_sorted_cats(d,cat) = begin
    cc = get_categories(d)
    catinfo = sort!([(c,get_parent_category(d,c)) for c in cc])
    filter!(x->x[1]!=x[2] && x[1] != cat,catinfo)
    @debug catinfo
    if length(catinfo) == 0 return [] end    #empty
    sorted = recurse_sort(cat,catinfo)
    if length(sorted) != length(catinfo)
        orig = [x[1] for x in catinfo]
        orphans = setdiff(orig,sorted)
        sort!(orphans)
        @debug "Missing (must be foreign) categories after sort: $orphans"
        append!(sorted,orphans)
    end
    return sorted
end

recurse_sort(cat,l) = begin
    final = []
    children = filter(x->x[2]==cat,l)
    for ch in children
        push!(final,ch[1])
        append!(final,recurse_sort(ch[1],l))
    end
    return final
end

"""
    Sort all of the names in `cat`, putting SU data names directly after
    their primary data names.
"""
sort_item_names(d,cat) = begin
    start_list = sort(get_names_in_cat(d,cat))
    # now find any su values
    sus = filter(start_list) do x
        direct = :purpose in propertynames(d[x][:type]) && d[x][:type].purpose[] in ("SU","su")
        direct || haskey(d[x],:import) && check_import_block(d,x,:type,:purpose,"SU")
    end
    @debug "All sus for $cat:" sus
    @debug "Linked items:" [(x,d[x][:name].linked_item_id) for x in sus]
    links = map(x->(x,lowercase(d[x][:name].linked_item_id[])),sus)
    for (s,l) in links
        si = findfirst(isequal(s),start_list)
        li = findfirst(isequal(l),start_list)
        if isnothing(si)
            @warn " $s not found in item list $start_list"
            continue
        end
        if isnothing(li)
            @warn "$l not found in item list $start_list"
            continue
        end
        if si != li+1
            deleteat!(start_list,si)
            if si < li
                insert!(start_list,li,s)
            else
                insert!(start_list,li+1,s)
            end
            @debug "Moved $s,$l from positions $si, $li"
            @debug "Cat list is now $start_list"
        end
    end
    return start_list
end
#
# **Output**
#
# DDL2 makes use of implicit values based on the block name. We
# ignore any columns contained in the 'implicit' const.
#

"""
    show(io::IOContext,::MIME"text/cif",ddl2_dic::DDL2_Dictionary)

Output `ddl2_dic` in CIF format. `IOContext` can be used to control the
output layout using the following keywords:

    strict: follow the IUCr layout rules
    
"""
show(io::IOContext,::MIME"text/cif",ddl2_dic::DDL2_Dictionary) = begin
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
        show_one_def(io,one_cat,cat_info,implicits=implicit_info,ordering=())
        items = sort(get_names_in_cat(ddl2_dic,one_cat))
        for one_item in items
            show_one_def(io,one_item,ddl2_dic[one_item],implicits=implicit_info,
                         ordering=())
        end
    end
    # And the looped top-level stuff
    for c in [:item_units_conversion,:item_units_list,:item_type_list,:dictionary_history,
              :sub_category,:category_group_list]
        if c in keys(ddl2_dic.block) && nrow(ddl2_dic[c]) > 0
            @debug "Now printing $c"
            show_loop(io,String(c),ddl2_dic[c],implicits=implicit_info,reflow=true)
        end
    end
end

"""
    show(io::IO,::MIME"text/cif",ddl2_dic::AbstractCifDictionary)
    
Output `ddl2_dic` to `IO` in CIF format
"""
show(io::IO,x::MIME"text/cif",ddl2_dic::AbstractCifDictionary;strict=false,kwargs...) = begin
    ic = IOContext(io,:strict=>strict)
    show(ic,x,ddl2_dic;kwargs...)
end
