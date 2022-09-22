function odd(number::Int)
    if number == 0
        return 0
    end
    while mod(number, 2) == 0
        number = div(number, 2)
    end
    return number
end

function get_min_wordlength(number::Int)
    return round(Int, max(log2(odd(abs(number))), 1), RoundUp)
end

function int2bin(number::Int)
    @assert number >= 0
    return reverse(digits(number, base=2))
end

function bin2csd!(vector_bin2csd::Vector{Int})
    @assert issubset(unique(vector_bin2csd), [-1,0,1])
    first_non_zero = 0
    for i in length(vector_bin2csd):-1:1
        if vector_bin2csd[i] != 0
            if first_non_zero == 0
                first_non_zero = i
            end
        elseif first_non_zero - i >= 2
            for j in (i+1):first_non_zero
                vector_bin2csd[j] = 0
            end
            vector_bin2csd[first_non_zero] = -1
            vector_bin2csd[i] = 1
            first_non_zero = i
        else
            first_non_zero = 0
        end
    end
    if first_non_zero > 1
        for j in 1:first_non_zero
            vector_bin2csd[j] = 0
        end
        vector_bin2csd[first_non_zero] = -1
        pushfirst!(vector_bin2csd, 1)
    end

    return vector_bin2csd
end

function bin2csd(vector_bin::Vector{Int})
    @assert issubset(unique(vector_bin), [-1,0,1])
    vector_csd = copy(vector_bin)
    return bin2csd!(vector_csd)
end

function int2csd(number::Int)
    return bin2csd!(int2bin(number))
end

function sum_nonzero(vector_binorcsd::Vector{Int})
    @assert issubset(unique(vector_binorcsd), [-1,0,1])
    sum = 0
    for i in vector_binorcsd
        if i != 0
            sum += 1
        end
    end
    return sum
end

function get_min_number_of_adders(C::Vector{Int})
    oddabsC = sort!(filter!(x -> x > 1, unique!(odd.(abs.(C)))), by=x->sum_nonzero(int2csd(x)))
    if isempty(oddabsC)
        return 0
    end
    if length(oddabsC) == 1
        return round(Int, log2(sum_nonzero(int2csd(oddabsC[1]))), RoundUp)
    end
    return round(Int, log2(sum_nonzero(int2csd(oddabsC[1]))), RoundUp)+sum(max(1, round(Int, log2(sum_nonzero(int2csd(oddabsC[i+1]))/sum_nonzero(int2csd(oddabsC[i]))), RoundUp)) for i in 1:(length(oddabsC)-1))
end

get_min_number_of_adders(C::Int) = get_min_number_of_adders([C])

function get_max_number_of_adders(C::Vector{Int})
    oddabsC = sort!(filter!(x -> x > 1, unique!(odd.(abs.(C)))), by=x->sum_nonzero(int2csd(x)))
    return sum(sum_nonzero(int2csd(val))-1 for val in oddabsC)
end
