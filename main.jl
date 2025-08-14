using TrimSimpleNonlinearSolve

function @main(argv::Vector{String})::Cint
    λ = try  # currently calling from `julia` and as binary yields different `argv`...
        parse(Float64, argv[1])
    catch
        parse(Float64, argv[2])
    end
    sol = TrimSimpleNonlinearSolve.minimize(λ, 2)
    # sol = TrimSimpleNonlinearSolve.minimize_nocache(λ, 2)
    # sol = TrimSimpleNonlinearSolve2.minimize_static(λ, 2)
    println(Core.stdout, sum(sol))
    return 0
end
