function mcm(model::Model,
             C::Vector{Int},
             ;wordlength::Int = 0,
             output_errors_dict::Dict{Int, Int}=Dict{Int, Int}(),
             output_errors::Vector{Int}=Vector{Int}(),
             output_error::Int=0,
             verbose::Bool = false,
             kwargs...
    )
    if isempty(C)
        return AdderGraph()
    end
    oddabsC = filter!(x -> x > 1, unique!(odd.(abs.(C))))
    if isempty(oddabsC)
        return AdderGraph(C)
    end
    if isempty(output_errors_dict) && isempty(output_errors)
        output_errors_dict = Dict{Int, Int}([output_value => output_error for output_value in C])
    elseif isempty(output_errors_dict)
        output_errors_dict = Dict{Int, Int}([C[i] => output_errors[i] for i in 1:length(C)])
    end
    @assert length(output_errors_dict) == length(unique(C))
    output_errors_odd_dict = Dict{Int, Float64}([odd(abs(C[i])) => Inf for i in 1:length(C)])
    for i in 1:length(C)
        if C[i] == 0
            continue
        end
        output_errors_odd_dict[odd(abs(C[i]))] = min(output_errors_odd_dict[odd(abs(C[i]))], output_errors_dict[C[i]]/(div(abs(C[i]), odd(abs(C[i])))))
    end
    output_errors = Vector{Int}([round(Int, output_errors_odd_dict[output_value], RoundDown) for output_value in oddabsC])
    if wordlength == 0
        wordlength = maximum(get_min_wordlength.(oddabsC))
    end
    verbose && println("Coefficients wordlength: $(wordlength)")
    if (1 << wordlength) - 1 < maximum(oddabsC)
        return AdderGraph()
    end
    !verbose && set_silent(model)

    addergraph = AdderGraph()

    optimize_increment!(model, oddabsC, wordlength,
        output_errors=output_errors,
        verbose=verbose; kwargs...)

    current_result = 1
    not_valid = true
    model[:valid_objective_value] = 0
    max_output_error = maximum(output_errors)
    while not_valid && has_values(model; result=current_result)
        addergraph = AdderGraph(C)
        for i in 1:model[:NA][current_result]
            node_shift = 0
            for s in -wordlength:0
                if round(Int, value(model[:Psias][i,s]; result = current_result)) == 1
                    node_shift = s
                    break
                end
            end
            input_shift = 0
            for s in 0:wordlength
                if round(Int, value(model[:phias][i,s]; result = current_result)) == 1
                    input_shift = s
                    break
                end
            end
            truncateleft = 0
            truncateright = 0
            if max_output_error != 0
                truncateleft = round(Int, value(model[:truncate_left_or_zeros][i]; result = current_result))
                truncateright = round(Int, value(model[:truncate_right_or_zeros][i]; result = current_result))
            end
            subtraction = [value(model[:cai_left_shsg][i]; result = current_result) < 0, value(model[:cai_right_sg][i]; result = current_result) < 0]
            left_addernode = InputEdge(get_origin(addergraph), input_shift+node_shift, subtraction[1], truncateleft)
            right_addernode = InputEdge(get_origin(addergraph), node_shift, subtraction[2], truncateright)
            if !isempty(get_addernodes_by_value(addergraph, round(Int, value(model[:cai][i,1]; result = current_result)))) && !isempty(get_addernodes_by_value(addergraph, round(Int, value(model[:cai][i,2]; result = current_result))))
                left_addernode = InputEdge(get_addernodes_by_value(addergraph, round(Int, value(model[:cai][i,1]; result = current_result)))[end], input_shift+node_shift, subtraction[1], truncateleft)
                right_addernode = InputEdge(get_addernodes_by_value(addergraph, round(Int, value(model[:cai][i,2]; result = current_result)))[end], node_shift, subtraction[2], truncateright)
            end
            if model[:has_ada]
                push_node!(addergraph,
                    AdderNode(round(Int, value(model[:ca][i]; result = current_result)),
                        [left_addernode, right_addernode],
                        round(Int, value(model[:ada][i]; result = current_result))
                    )
                )
            else
                push_node!(addergraph,
                    AdderNode(round(Int, value(model[:ca][i]; result = current_result)),
                        [left_addernode, right_addernode]
                    )
                )
            end
        end
        not_valid = !isvalid(addergraph)
        if not_valid
            addergraph = AdderGraph()
        else
            model[:valid_objective_value] = objective_value(model; result = current_result)
        end
        current_result = current_result + 1
    end

    return addergraph
end
