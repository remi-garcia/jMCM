using Pkg
Pkg.activate("$(@__DIR__())/../")

using AdderGraphs, JuMP, Gurobi, jMCM

include("$(@__DIR__())/utils.jl")
#include("$(@__DIR__())/read_write.jl")


function benchmarks(which_benchmark::Int, which_mcm::String, mincrit::Bool=false, use_dsp::Bool=false, with_pipelining_cost::Bool=false)
    wordlength_data = 8
    wordlength_in = 0
    output_error_init = output_error = 0
    resultname = "mcm"
    if which_mcm == "mcmb"
        wordlength_in = wordlength_data
        output_error_init = output_error = 0
        resultname = "mcmb"
    elseif length(which_mcm) >= 4 && which_mcm[1:4] == "tmcm"
        wordlength_in = wordlength_data
        if length(which_mcm) > 4
            output_error_init = output_error = -parse(Int, which_mcm[5:end])
        else
            output_error_init = output_error = -1
        end
        resultname = "tmcm"
    end
    if mincrit
        resultname *= "cp"
    end
    if with_pipelining_cost
        resultname = "p"*resultname
    end
    max_dsp = 0
    cost_dsp = 0.0
    if use_dsp
        max_dsp = 3
    end
    use_rpag = false
    if which_mcm == "rpag"
        resultname = "rpag"
        use_rpag = true
        max_dsp = 0
        use_dsp = false
        mincrit = false
    end

    all_benchmarks = Vector{Tuple{String, String, Int, Int, Int, Vector{Int}, Vector{Int}}}()
    open("$(@__DIR__)/benchmarks.csv") do file
        lines = readlines(file)
        for line in lines[2:end]
            line_data = split(line, ",")
            push!(all_benchmarks,
                (line_data[1], # name
                line_data[2], # filter_type
                parse(Int, line_data[3]), # wordlength
                parse(Int, line_data[4]), # number_of_coefficients
                parse(Int, line_data[5]), # number_of_unique_coefficients
                parse.(Int, split(line_data[6])), # coefficients
                parse.(Int, split(line_data[7]))) # unique_coefficients
            )
        end
    end

    benchmark_info = all_benchmarks[which_benchmark]
    println("\n\n\n\n----- Problem $(benchmark_info[1]) -----\n\n")
    println("$which_mcm -- $resultname")
    println("wordlength_in: $wordlength_in")
    println("output_error: $output_error")
    C = copy(benchmark_info[6])
    wordlength_out_full_precision = round(Int, log2((2^wordlength_data-1)*maximum(abs.(C))), RoundUp)
    wordlength_out_current_precision = wordlength_out_full_precision
    epsilon_frac = -output_error_init
    # oddabsC = filter!(x -> x > 1, unique!(odd.(abs.(C))))
    oddabsC = filter!(x -> x >= 1, unique!(odd.(abs.(C))))
    println("Coefficients: $oddabsC")
    if output_error_init < 0
        if output_error_init == -1
            wordlength_out_current_precision = wordlength_data
        else
            # wordlength_out_current_precision = div(wordlength_out_full_precision, -output_error_init)+(mod(wordlength_out_full_precision, -output_error_init) == 0 ? 0 : 1)
            wordlength_out_current_precision = wordlength_out_full_precision-div(wordlength_out_full_precision, -output_error_init)
        end
        if !isempty(oddabsC)
            if output_error_init == -1
                output_error = 2^(round(log2(maximum(oddabsC)), RoundUp)-1)
            else
                output_error = 2^(wordlength_out_full_precision-wordlength_out_current_precision)
            end
        else
            output_error = 0
        end
    end
    println("wordlength_out_full_precision: $wordlength_out_full_precision")
    println("wordlength_out_current_precision: $wordlength_out_current_precision")

    output_errors = Dict{Int, Int}([oddcoeff => output_error for oddcoeff in oddabsC])
    for i in 1:length(oddabsC)
        oddcoeff = oddabsC[i]
        for coeff in C
            if odd(abs(coeff)) == oddcoeff
                output_errors[oddcoeff] = min(output_errors[oddcoeff], round(Int, output_error/(div(abs(coeff), oddcoeff)), RoundDown))
            end
        end
    end

    if !use_rpag
        model = Model(Gurobi.Optimizer)
        set_optimizer_attributes(model, "Threads" => 4)
        set_optimizer_attributes(model, "PoolSolutions" => 100)
        #set_silent(model)
        set_time_limit_sec(model, 1800)
        @time ag = mcm(model, oddabsC, use_mcm_warmstart=true, with_pipelining_cost=with_pipelining_cost, adder_cost=Int(!with_pipelining_cost), use_mcm_warmstart_time_limit_sec=30.0, wordlength_in=wordlength_in, output_errors_dict=output_errors, verbose=true, minimize_critical_path=mincrit, nb_adders_start=get_max_number_of_adders(oddabsC), use_warmstart=true)
        println("Solving time: $(model[:total_solve_time])")

        not_opt = ""
        if termination_status(model) != MOI.OPTIMAL
            not_opt = "*"
        end
        if model[:valid_objective_value] != objective_value(model; result = 1)
            not_opt = "**"
        end

        open("$(@__DIR__)/results_$(resultname).csv", "a") do writefile
            ag_name = "$(benchmark_info[1])_$(resultname)$(epsilon_frac != 0 ? epsilon_frac : "").txt"
            # benchmark_name, ag_name, method, minimize_ad, pipeline, solve_time, NA, AD, nb_registers, datawl, Bits, nb_registers_bits, max_epsilon, wloutfullprecision, wlout, epsilon_frac
            write(writefile, "$(benchmark_info[1]), $(ag_name), $(resultname), $(mincrit), $(with_pipelining_cost), $(model[:total_solve_time])$not_opt, $(length(get_nodes(ag))), $(get_adder_depth(ag)), $(get_nb_registers(ag)-length(get_nodes(ag))), $(wordlength_data), $(compute_total_nb_onebit_adders(ag, wordlength_data)), $(get_nb_register_bits(ag, wordlength_data)-compute_total_nb_onebit_adders(ag, wordlength_data)), $(maximum(values(output_errors))), $(wordlength_out_full_precision), $(wordlength_out_current_precision), 1/$(epsilon_frac)\n")
        end
        open("$(@__DIR__)/addergraphs/$(benchmark_info[1])_$(resultname)$(epsilon_frac != 0 ? epsilon_frac : "").txt", "w") do writefile
            write(writefile, "$(write_addergraph(ag, pipeline=with_pipelining_cost))\n$(write_addergraph_truncations(ag))\n")
        end
    else
        ag = rpag(C, with_register_cost=with_pipelining_cost)
        open("$(@__DIR__)/results_$(resultname).csv", "a") do writefile
            ag_name = "$(benchmark_info[1])_$(resultname)$(epsilon_frac != 0 ? epsilon_frac : "").txt"
            # benchmark_name, ag_name, method, minimize_ad, pipeline, solve_time, NA, AD, nb_registers, datawl, Bits, nb_registers_bits, max_epsilon, wloutfullprecision, wlout, epsilon_frac
            write(writefile, "$(benchmark_info[1]), $(ag_name), $(resultname), $(mincrit), $(with_pipelining_cost), -, $(length(get_nodes(ag))), $(get_adder_depth(ag)), $(get_nb_registers(ag)-length(get_nodes(ag))), $(wordlength_data), $(compute_total_nb_onebit_adders(ag, wordlength_data)), $(get_nb_register_bits(ag, wordlength_data)-compute_total_nb_onebit_adders(ag, wordlength_data)), $(maximum(values(output_errors))), $(wordlength_out_full_precision), $(wordlength_out_current_precision), 1/$(epsilon_frac)\n")
        end
        open("$(@__DIR__)/addergraphs/$(benchmark_info[1])_$(resultname)$(epsilon_frac != 0 ? epsilon_frac : "").txt", "w") do writefile
            write(writefile, "$(write_addergraph(ag, pipeline=with_pipelining_cost))\n$(write_addergraph_truncations(ag))\n")
        end
    end


    return nothing
end


if length(ARGS) > 0
    if length(ARGS) >= 3
        benchmarks(parse(Int, ARGS[1]), ARGS[2], "cp" in ARGS[3:end], "dsp" in ARGS[3:end], "pipeline" in ARGS[3:end])
    else
        benchmarks(parse(Int, ARGS[1]), ARGS[2])
    end
end
