module TrimSimpleNonlinearSolve2
# using SimpleNonlinearSolve
using NonlinearSolve
using ForwardDiff
using LinearAlgebra
using StaticArrays
using LinearSolve
const LS = LinearSolve
# using FixedSizeArrays
# import NonlinearSolve.SciMLBase.get_root_indp

# NonlinearSolve.SciMLBase.get_root_indp(prob::NonlinearLeastSquaresProblem) = prob.p

function f(u, p)
    L, U = cholesky(p.Σ)
    rhs = (u .* u .- p.λ)
    # linprob = LinearProblem(Matrix(L), rhs)
    # linprob = LinearProblem(Matrix(L), rhs)
    linprob = LinearProblem(L, rhs)
    # alg = LS.QRFactorization()
    # alg = LS.GenericLUFactorization()
    alg = LS.DirectLdiv!()
    # alg = LS.DirectLDiv()
    # sol = LinearSolve.solve(linprob, alg; aliases=LinearAliasSpecifier(alias_A=false))
    sol = LinearSolve.solve(linprob, alg)
    return sol.u 
end

# function f(u, p)
#     L, U = cholesky(p.Σ)
#     return L \ (u .* u .- p.λ)
# end

function minimize(λ=1.0)
    ps = (; λ, Σ=hermitianpart(rand(2,2) + 2*I))
    u₀ = rand(2)
    prob = NonlinearLeastSquaresProblem{false}(f, u₀, ps)
    autodiff = AutoForwardDiff(; chunksize=1)
    sol = solve(prob, SimpleTrustRegion(; autodiff))
    return sol.u
end

function minimize_static(λ=1.0)
    ps = (; λ, Σ=SMatrix{2,2}(hermitianpart(rand(2,2) + 2*I)))
    u₀ = SVector{2}(rand(2))
    prob = NonlinearLeastSquaresProblem{false}(f, u₀, ps)
    autodiff = AutoForwardDiff(chunksize=1)
    sol = solve(prob, SimpleTrustRegion(; autodiff))
    return sol.u
end

# function @main(argv::Vector{String})::Cint
#     u = minimize()
#     println(Core.stdout, u)
#     return 0
# end

end # module TrimSimpleNonlinearSolve
