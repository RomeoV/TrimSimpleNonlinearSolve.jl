module TrimSimpleNonlinearSolve
using NonlinearSolveFirstOrder
using DiffEqBase
import DiffEqBase.anyeltypedual
using ADTypes: AutoForwardDiff
using ForwardDiff
using LinearAlgebra
using StaticArrays
using LinearSolve
import SciMLBase
const LS = LinearSolve
function f(u, p)
    L, U = cholesky(p.Σ)
    rhs = (u .* u .- p.λ)
    # linprob = LinearProblem(Matrix(L), rhs)
    # alg = LS.GenericLUFactorization()
    # sol = LinearSolve.solve(linprob, alg)
    return L' * rhs
end

struct MyParams{T, M}
    λ::T
    Σ::M
end
# DiffEqBase.anyeltypedual(::MyParams) = Any

const autodiff = AutoForwardDiff(; chunksize = 1)
# const alg = TrustRegion(; autodiff, linsolve = LS.CholeskyFactorization())
const alg = LevenbergMarquardt(; autodiff, linsolve = LS.CholeskyFactorization())

function minimize(x, n)
    prob = NonlinearLeastSquaresProblem{false}(f, rand(n), MyParams(rand(), hermitianpart(rand(n, n) + 2I)))
    cache = init(prob, alg)
    ps = MyParams(x, hermitianpart(rand(n, n) + 2I))
    reinit!(cache, rand(n); p = ps)
    solve!(cache)
    return cache.u
end

function minimize_nocache(x, n)
    prob = NonlinearLeastSquaresProblem{false}(f, rand(n), MyParams(rand(), hermitianpart(rand(n, n) + 2I)))
    return sol = solve(prob, alg)
end
end # module TrimSimpleNonlinearSolve
