# run with timeout
# https://discourse.julialang.org/t/53876/3

function run_with_timeout(command; timelimit::T=0.0, sleepstep::S=0.1, kwargs...) where T <: Real where S <: Real
    if iszero(timelimit)
        cmd = run(command; wait=true)
        return success(cmd)
    end
    pout = Pipe()
    cmd = run(pipeline(command; stdout = pout); wait=false)
    start_time = time_ns()
    while (time_ns()-start_time)*1e-9 < timelimit
        if !process_running(cmd)
            close(pout.in)
            println(read(pout, String))
            return success(cmd)
        end
        sleep(sleepstep)
    end
    if !process_running(cmd)
        close(pout.in)
        println(read(pout, String))
        return success(cmd)
    end
    kill(cmd)
    return false
end
