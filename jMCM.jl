using JuMP, Gurobi
using AdderGraphs

include("src/jMCM.jl")
using .jMCM

mutable struct jMCM_args
    target_consts::Vector{Int}
    timelimit::Union{Nothing, Float64}
    wIn::Int
    wOut::Int
    pipeline::Bool
    verbose::Bool
    min_ad::Bool
    nb_adders_start::Int
    use_rpag::Bool
    use_mcm::Bool
    threads::Int
    ws_timelimit::Float64
    file_ag::String
    file_vhdl::String
end

function jMCM_args()
    return jMCM_args(Vector{Int}(), nothing, 0, 0, false, false, false, 0, false, false, 0, 0, "addergraph.txt", "addergraph.vhdl")
end

function read_args(args)
    all_args = jMCM_args()
    for current_arg in args
        if !occursin("=", current_arg)
            push!(all_args.target_consts, parse(Int, current_arg))
        else
            current_kw, current_value = split(current_arg, "=")
            if current_kw == "timelimit"
                all_args.timelimit = parse(Float64, current_value)
            elseif current_kw == "wIn"
                all_args.wIn = parse(Int, current_value)
            elseif current_kw == "wOut"
                all_args.wOut = parse(Int, current_value)
            elseif current_kw == "pipeline"
                all_args.pipeline = parse(Bool, current_value)
            elseif current_kw == "verbose"
                all_args.verbose = parse(Bool, current_value)
            elseif current_kw == "min_ad"
                all_args.min_ad = parse(Bool, current_value)
            elseif current_kw == "nb_adders_start"
                all_args.nb_adders_start = parse(Int, current_value)
            elseif current_kw == "use_rpag"
                all_args.use_rpag = parse(Bool, current_value)
            elseif current_kw == "use_mcm"
                all_args.use_mcm = parse(Bool, current_value)
            elseif current_kw == "threads"
                all_args.threads = parse(Int, current_value)
            elseif current_kw == "ws_timelimit"
                all_args.ws_timelimit = parse(Float64, current_value)
            else
                println("Unrecognized keyword `$current_kw` ignored")
            end
        end
    end
    return all_args
end

function main(args)
    if isempty(args)
        println("Need parameters, usage example: julia jMCM.jl 5 11")
        return nothing
    end
    all_args = read_args(args)
    model = Model(Gurobi.Optimizer)
    if all_args.threads != 0
        MOI.set(model, MOI.NumberOfThreads(), all_args.threads)
    end
    # set_optimizer_attributes(model, "PoolSolutions" => 100)
    !all_args.verbose && set_silent(model)
    if !isnothing(all_args.timelimit)
        set_time_limit_sec(model, all_args.timelimit)
    end
    ag = mcm(model,
             all_args.target_consts,
             use_mcm_warmstart=all_args.use_mcm,
             use_mcm_warmstart_time_limit_sec=all_args.ws_timelimit,
             wordlength_in=all_args.wIn,
             verbose=all_args.verbose,
             minimize_adder_depth=all_args.min_ad,
             nb_adders_start=all_args.nb_adders_start,
             use_warmstart=all_args.use_rpag
    )

    return nothing
end

main(ARGS)
