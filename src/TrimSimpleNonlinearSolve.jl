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
    # inlined and simplified version of
    # ````
    # cache = init(prob, alg; p=MyParams(x))
    # ````
    cache = let u0 = prob.u0, p = prob.p
        _prob = NonlinearSolveFirstOrder.DiffEqBase.get_concrete_problem(prob, false; u0=u0, p=p)
        _alg = NonlinearSolveFirstOrder.DiffEqBase.prepare_alg(alg, _prob.u0, _prob.p, _prob)
        NonlinearSolveFirstOrder.DiffEqBase.init_call(_prob, _alg)
    end

    solve!(cache)
    return cache.u
end
end # module TrimSimpleNonlinearSolve
