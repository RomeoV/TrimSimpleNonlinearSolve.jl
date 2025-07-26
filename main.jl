using TrimSimpleNonlinearSolve2

function @main(argv::Vector{String})::Cint
    λ = try 
        parse(Float64, argv[1])
    catch
        parse(Float64, argv[2])
    end
    sol = TrimSimpleNonlinearSolve2.minimize(λ)
    # sol = TrimSimpleNonlinearSolve2.minimize_static(λ)
    println(Core.stdout, sum(sol))
    return 0
end
