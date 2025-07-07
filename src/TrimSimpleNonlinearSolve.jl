module TrimSimpleNonlinearSolve
using SimpleNonlinearSolve
using DifferentiationInterface
using FiniteDiff
using ForwardDiff
using LinearAlgebra
using StaticArrays
using FixedSizeArrays
import FixedSizeArrays: FixedSizeMatrix as FSM, FixedSizeVector as FSV, FixedSizeArray as FSA

include("read_csv.jl")

load_mat(path) = let
    data = TrimmableCSV.parse_data(IOBuffer(read(path, String)), @NamedTuple{a::Float64, b::Float64})
    [data.a data.b]
end

function minimize(p, u₀)
    function f(u, p)
        L, U = cholesky(p.Σ)
        return L \ (u .* u .- p.λ)
    end
    prob = NonlinearLeastSquaresProblem{false}(f, u₀, p)
    autodiff = AutoForwardDiff(chunksize = 1)
    sol = solve(prob, SimpleTrustRegion(; autodiff))
    return sol.u
end

function main(λ = 1.0)
    Σ = load_mat(joinpath(pkgdir(@__MODULE__), "data", "mat.csv"))
    u1 = minimize((; λ, Σ = SMatrix{2, 2}(Σ)), SVector{2}(rand(2)))
    u2 = minimize((; λ, Σ = (FSM{Float64}(undef, 2, 2) .= Σ)), FSV(rand(2)))
    return (u1 + u2) / 2
    # return u2
end

Base.@ccallable function main(argc::Cint, argv::Ptr{Ptr{UInt8}})::Cint
    cstr = unsafe_load(argv, 2)
    jlstr = unsafe_string(cstr)
    λ = parse(Float64, jlstr)
    sol = main(λ)
    println(Core.stdout, sum(sol))
    return 0
end

end # module TrimSimpleNonlinearSolve
