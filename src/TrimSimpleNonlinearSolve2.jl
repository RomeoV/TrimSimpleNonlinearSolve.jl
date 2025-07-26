module TrimSimpleNonlinearSolve2
# using SimpleNonlinearSolve
# using SimpleNonlinearSolve
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
# using FixedSizeArrays
# import NonlinearSolve.SciMLBase.get_root_indp

# NonlinearSolve.SciMLBase.get_root_indp(prob::NonlinearLeastSquaresProblem) = prob.p
#
# Core.println(SciMLBase.EnumX.namemap(SciMLBase.ReturnCode.Success))
# Core.println(Base.Enums.namemap(SciMLBase.ReturnCode.Success))
Core.println(SciMLBase.EnumX.symbol_map(SciMLBase.ReturnCode.T))

function f(u, p)
    L, U = cholesky(p.Σ)
    rhs = (u .* u .- p.λ)
    # linprob = LinearProblem(Matrix(L), rhs)
    # linprob = LinearProblem(Matrix(L), rhs)
    linprob = LinearProblem(Matrix(L), rhs)
    # alg = LS.QRFactorization()
    alg = LS.GenericLUFactorization()
    # alg = LS.DirectLdiv!()
    # alg = LS.DirectLDiv()
    # sol = LinearSolve.solve(linprob, alg; aliases=LinearAliasSpecifier(alias_A=false))
    sol = LinearSolve.solve(linprob, alg)
    return sol.u 
end

struct MyParams{T, M}
    λ::T
    Σ::M
end
DiffEqBase.anyeltypedual(::MyParams) = Any

const autodiff = AutoForwardDiff(; chunksize=1)
const alg = TrustRegion(; autodiff, linsolve=LS.CholeskyFactorization())
const prob = NonlinearLeastSquaresProblem{false}(f, rand(2), MyParams(rand(), hermitianpart(rand(2,2)+2I)))
const cache = init(prob, alg)

function minimize(x)
    ps = MyParams(x, hermitianpart(rand(2,2)+2I))
    # prob_ = remake(prob, u0=rand(2), p=ps)
    reinit!(cache, rand(2); p=ps)
    # cache = init(prob_, alg)
    solve!(cache)
    return cache.u
end

# function f(u, p)
#     L, U = cholesky(p.Σ)
#     return L \ (u .* u .- p.λ)
# end

# function minimize(λ=1.0)
#     ps = MyParams(λ, hermitianpart(rand(2,2) + 2*I))
#     u₀ = rand(2)
#     prob_ = remake(prob, u0 = u₀, p=ps)
#     # alg = SimpleTrustRegion(; autodiff)
#     # alg = LevenbergMarquardt(; autodiff, linsolve=LS.CholeskyFactorization())
#     # alg = GaussNewton(; autodiff)
#     sol = solve(prob_, alg, cache)
#     return sol.u
# end

# function minimize_static(λ=1.0)
#     ps = (; λ, Σ=SMatrix{2,2}(hermitianpart(rand(2,2) + 2*I)))
#     u₀ = SVector{2}(rand(2))
#     prob = NonlinearLeastSquaresProblem{false}(f, u₀, ps)
#     autodiff = AutoForwardDiff(chunksize=1)
#     sol = solve(prob, SimpleTrustRegion(; autodiff))
#     return sol.u
# end

# function @main(argv::Vector{String})::Cint
#     u = minimize()
#     println(Core.stdout, u)
#     return 0
# end

end # module TrimSimpleNonlinearSolve
