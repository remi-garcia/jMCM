# rpag.jl
# Run rpag and read the output with AdderGraphs

# Requirement: run_with_timeout
include("$(@__DIR__())/run_with_timeout.jl")

using AdderGraphs

function generate_rpag_cmd(v::Vector{Int}; file_output::String="", with_register_cost::Bool=false, nb_extra_stages::Int=0, kwargs...)
    return "rpag --file_output=$(file_output) $(with_register_cost ? "" : "--cost_model=hl_min_ad ")$(nb_extra_stages==0 ? "" : "--no_of_extra_stages=$(nb_extra_stages) ")"*join(v, " ")
end


function rpagcall(rpag_cmd::String; file_output::String, use_rpag_lib::Bool=false, kwargs...)
    argv = Vector{String}(string.(split(rpag_cmd)))
    rpag_success = true
    if use_rpag_lib
        ccall((:main, "librpag"), Cint, (Cint, Ptr{Ptr{UInt8}}), length(argv), argv)
        Base.Libc.flush_cstdio()
    else
        try
            rpag_success = run_with_timeout(`$(argv)`; kwargs...)
            rpag_success = true
        catch
            rpag_success = false
        end
    end
    return read(file_output, String), rpag_success
end


function rpag(C::Vector{Int}; kwargs...)
    if isempty(Base.Libc.Libdl.find_library("librpag"))
        @warn "librpag not found"
        return AdderGraph()
    end
    filename = tempname()
    str_result, rpag_success = rpagcall(generate_rpag_cmd(C; file_output=filename, kwargs...); file_output=filename, kwargs...)
    s = split(str_result, "\n")
    # Workaround
    if isempty(s) || (length(s) == 1 && isempty(s[1]))
        @warn "rpag failed to produce an adder graph"
        return AdderGraph()
    end
    addergraph_str = string(s[1])
    addergraph = read_addergraph(addergraph_str)
    ag_outputs = get_outputs(addergraph)
    for c in C
        if c == 1
            push_output!(addergraph, 1)
        end
        if !(c in ag_outputs)
            @warn "rpag did not produce output value $(c)"
        end
    end
    return addergraph
end
