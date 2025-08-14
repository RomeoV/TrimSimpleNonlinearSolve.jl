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
const _prob = NonlinearSolveFirstOrder.DiffEqBase.get_concrete_problem(prob, false; u0=prob.u0, p=prob.p)
const _alg = NonlinearSolveFirstOrder.DiffEqBase.prepare_alg(alg, _prob.u0, _prob.p, _prob)

function minimize(x)
    # inlined and simplified version of
    # ````
    # cache = init(prob, alg; p=MyParams(x))
    # ````

    # this takes us here: https://github.com/SciML/NonlinearSolve.jl/blob/b37b31b22a6650c773a4fdef8ca220f4e8815051/lib/NonlinearSolveFirstOrder/src/solve.jl#L123-L129
    cache = NonlinearSolveFirstOrder.DiffEqBase.__init(_prob, _alg)

    solve!(cache)
    return cache.u
end
end # module TrimSimpleNonlinearSolve
