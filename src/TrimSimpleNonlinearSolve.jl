module TrimSimpleNonlinearSolve
using NonlinearSolveFirstOrder
using ADTypes: AutoForwardDiff
using LinearSolve: CholeskyFactorization

function f(u, p)
    return (u .- p.λ) .^ 2
end

struct MyParams{T}
    λ::T
end

const autodiff = AutoForwardDiff(; chunksize=1)
const alg = LevenbergMarquardt(; autodiff, linsolve=CholeskyFactorization())
const prob = NonlinearLeastSquaresProblem{false}(f, rand(2), MyParams(rand()))

function minimize(x)
    cache = init(prob, alg; p=MyParams(x))
    solve!(cache)
    return cache.u
end
end # module TrimSimpleNonlinearSolve
