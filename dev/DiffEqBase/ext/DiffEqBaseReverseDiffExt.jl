module DiffEqBaseReverseDiffExt

using DiffEqBase
import DiffEqBase: value
import ReverseDiff
import DiffEqBase.ArrayInterface

function DiffEqBase.anyeltypedual(::Type{T},
        ::Type{Val{counter}} = Val{0}) where {counter} where {
        V, D, N, VA, DA, T <: ReverseDiff.TrackedArray{V, D, N, VA, DA}}
    DiffEqBase.anyeltypedual(V, Val{counter})
end

DiffEqBase.value(x::Type{ReverseDiff.TrackedReal{V, D, O}}) where {V, D, O} = V
function DiffEqBase.value(x::Type{
        ReverseDiff.TrackedArray{V, D, N, VA, DA},
}) where {V, D,
        N, VA,
        DA}
    Array{V, N}
end
DiffEqBase.value(x::ReverseDiff.TrackedReal) = x.value
DiffEqBase.value(x::ReverseDiff.TrackedArray) = x.value

DiffEqBase.unitfulvalue(x::Type{ReverseDiff.TrackedReal{V, D, O}}) where {V, D, O} = V
function DiffEqBase.unitfulvalue(x::Type{
        ReverseDiff.TrackedArray{V, D, N, VA, DA},
}) where {V, D,
        N, VA,
        DA}
    Array{V, N}
end
DiffEqBase.unitfulvalue(x::ReverseDiff.TrackedReal) = x.value
DiffEqBase.unitfulvalue(x::ReverseDiff.TrackedArray) = x.value

# Force TrackedArray from TrackedReal when reshaping W\b
DiffEqBase._reshape(v::AbstractVector{<:ReverseDiff.TrackedReal}, siz) = reduce(vcat, v)

DiffEqBase.promote_u0(u0::ReverseDiff.TrackedArray, p::ReverseDiff.TrackedArray, t0) = u0
function DiffEqBase.promote_u0(u0::AbstractArray{<:ReverseDiff.TrackedReal},
        p::ReverseDiff.TrackedArray, t0)
    u0
end
function DiffEqBase.promote_u0(u0::ReverseDiff.TrackedArray,
        p::AbstractArray{<:ReverseDiff.TrackedReal}, t0)
    u0
end
function DiffEqBase.promote_u0(u0::AbstractArray{<:ReverseDiff.TrackedReal},
        p::AbstractArray{<:ReverseDiff.TrackedReal}, t0)
    u0
end
DiffEqBase.promote_u0(u0, p::ReverseDiff.TrackedArray, t0) = ReverseDiff.track(u0)
function DiffEqBase.promote_u0(
        u0, p::ReverseDiff.TrackedArray{T}, t0) where {T <: ReverseDiff.ForwardDiff.Dual}
    ReverseDiff.track(T.(u0))
end
DiffEqBase.promote_u0(u0, p::AbstractArray{<:ReverseDiff.TrackedReal}, t0) = eltype(p).(u0)

# Support adaptive with non-tracked time
@inline function DiffEqBase.ODE_DEFAULT_NORM(u::ReverseDiff.TrackedArray, t)
    sqrt(sum(abs2, DiffEqBase.value(u)) / length(u))
end
@inline function DiffEqBase.ODE_DEFAULT_NORM(
        u::AbstractArray{<:ReverseDiff.TrackedReal, N},
        t) where {N}
    sqrt(sum(x -> DiffEqBase.ODE_DEFAULT_NORM(x[1], x[2]),
        zip((DiffEqBase.value(x) for x in u), Iterators.repeated(t))) / length(u))
end
@inline function DiffEqBase.ODE_DEFAULT_NORM(u::Array{<:ReverseDiff.TrackedReal, N},
        t) where {N}
    sqrt(sum(x -> DiffEqBase.ODE_DEFAULT_NORM(x[1], x[2]),
        zip((DiffEqBase.value(x) for x in u), Iterators.repeated(t))) / length(u))
end
@inline function DiffEqBase.ODE_DEFAULT_NORM(u::ReverseDiff.TrackedReal, t)
    abs(DiffEqBase.value(u))
end

# Support TrackedReal time, don't drop tracking on the adaptivity there
@inline function DiffEqBase.ODE_DEFAULT_NORM(u::ReverseDiff.TrackedArray,
        t::ReverseDiff.TrackedReal)
    sqrt(sum(abs2, u) / length(u))
end
@inline function DiffEqBase.ODE_DEFAULT_NORM(
        u::AbstractArray{<:ReverseDiff.TrackedReal, N},
        t::ReverseDiff.TrackedReal) where {N}
    sqrt(sum(x -> DiffEqBase.ODE_DEFAULT_NORM(x[1], x[2]), zip(u, Iterators.repeated(t))) /
         length(u))
end
@inline function DiffEqBase.ODE_DEFAULT_NORM(u::Array{<:ReverseDiff.TrackedReal, N},
        t::ReverseDiff.TrackedReal) where {N}
    sqrt(sum(x -> DiffEqBase.ODE_DEFAULT_NORM(x[1], x[2]), zip(u, Iterators.repeated(t))) /
         length(u))
end
@inline function DiffEqBase.ODE_DEFAULT_NORM(u::ReverseDiff.TrackedReal,
        t::ReverseDiff.TrackedReal)
    abs(u)
end

# `ReverseDiff.TrackedArray`
function DiffEqBase.solve_up(prob::DiffEqBase.AbstractDEProblem,
        sensealg::Union{
            SciMLBase.AbstractOverloadingSensitivityAlgorithm,
            Nothing}, u0::ReverseDiff.TrackedArray,
        p::ReverseDiff.TrackedArray, args...; kwargs...)
    ReverseDiff.track(DiffEqBase.solve_up, prob, sensealg, u0, p, args...; kwargs...)
end

function DiffEqBase.solve_up(prob::DiffEqBase.AbstractDEProblem,
        sensealg::Union{
            SciMLBase.AbstractOverloadingSensitivityAlgorithm,
            Nothing}, u0, p::ReverseDiff.TrackedArray,
        args...; kwargs...)
    ReverseDiff.track(DiffEqBase.solve_up, prob, sensealg, u0, p, args...; kwargs...)
end

function DiffEqBase.solve_up(prob::DiffEqBase.AbstractDEProblem,
        sensealg::Union{
            SciMLBase.AbstractOverloadingSensitivityAlgorithm,
            Nothing}, u0::ReverseDiff.TrackedArray, p,
        args...; kwargs...)
    ReverseDiff.track(DiffEqBase.solve_up, prob, sensealg, u0, p, args...; kwargs...)
end

# `AbstractArray{<:ReverseDiff.TrackedReal}`
function DiffEqBase.solve_up(prob::DiffEqBase.AbstractDEProblem,
        sensealg::Union{
            SciMLBase.AbstractOverloadingSensitivityAlgorithm,
            Nothing},
        u0::AbstractArray{<:ReverseDiff.TrackedReal},
        p::AbstractArray{<:ReverseDiff.TrackedReal}, args...;
        kwargs...)
    DiffEqBase.solve_up(prob, sensealg, ArrayInterface.aos_to_soa(u0),
        ArrayInterface.aos_to_soa(p), args...;
        kwargs...)
end

function DiffEqBase.solve_up(prob::DiffEqBase.AbstractDEProblem,
        sensealg::Union{
            SciMLBase.AbstractOverloadingSensitivityAlgorithm,
            Nothing}, u0,
        p::AbstractArray{<:ReverseDiff.TrackedReal},
        args...; kwargs...)
    DiffEqBase.solve_up(
        prob, sensealg, u0, ArrayInterface.aos_to_soa(p), args...; kwargs...)
end

function DiffEqBase.solve_up(prob::DiffEqBase.AbstractDEProblem,
        sensealg::Union{
            SciMLBase.AbstractOverloadingSensitivityAlgorithm,
            Nothing}, u0::ReverseDiff.TrackedArray,
        p::AbstractArray{<:ReverseDiff.TrackedReal},
        args...; kwargs...)
    DiffEqBase.solve_up(
        prob, sensealg, u0, ArrayInterface.aos_to_soa(p), args...; kwargs...)
end

function DiffEqBase.solve_up(prob::DiffEqBase.DEProblem,
        sensealg::Union{
            SciMLBase.AbstractOverloadingSensitivityAlgorithm,
            Nothing},
        u0::AbstractArray{<:ReverseDiff.TrackedReal}, p,
        args...; kwargs...)
    DiffEqBase.solve_up(
        prob, sensealg, ArrayInterface.aos_to_soa(u0), p, args...; kwargs...)
end

function DiffEqBase.solve_up(prob::DiffEqBase.DEProblem,
        sensealg::Union{
            SciMLBase.AbstractOverloadingSensitivityAlgorithm,
            Nothing},
        u0::AbstractArray{<:ReverseDiff.TrackedReal}, p::ReverseDiff.TrackedArray,
        args...; kwargs...)
    DiffEqBase.solve_up(
        prob, sensealg, ArrayInterface.aos_to_soa(u0), p, args...; kwargs...)
end

# Required becase ReverseDiff.@grad function DiffEqBase.solve_up is not supported!
import DiffEqBase: solve_up
ReverseDiff.@grad function solve_up(prob, sensealg, u0, p, args...; kwargs...)
    out = DiffEqBase._solve_adjoint(prob, sensealg, ReverseDiff.value(u0),
        ReverseDiff.value(p),
        SciMLBase.ReverseDiffOriginator(), args...; kwargs...)
    function actual_adjoint(_args...)
        original_adjoint = out[2](_args...)
        if isempty(args) # alg is missing
            tuple(original_adjoint[1:4]..., original_adjoint[6:end]...)
        else
            original_adjoint
        end
    end
    Array(out[1]), actual_adjoint
end

end
