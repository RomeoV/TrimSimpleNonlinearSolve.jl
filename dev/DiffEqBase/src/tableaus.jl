"""
$(TYPEDEF)

Holds a tableau which defines an explicit Runge-Kutta method.
"""
mutable struct ExplicitRKTableau{MType <: AbstractMatrix, VType <: AbstractVector, S} <:
               ODERKTableau
    A::MType
    c::VType
    α::VType
    αEEst::VType
    d::VType # dense output coefficients
    stages::Int
    order::Int
    adaptiveorder::Int #The lower order of the pair. Only used for adaptivity.
    fsal::Bool
    stability_size::S
end
function ExplicitRKTableau(A::MType, c::VType, α::VType, order;
        adaptiveorder = 0, αEEst = similar(α, 0),
        fsal = false, stability_size = 0.0,
        d = similar(α, 0)) where {MType, VType}
    S = typeof(stability_size)
    ExplicitRKTableau{MType, VType, S}(A, c, α, αEEst, d, length(α), order, adaptiveorder,
        fsal, stability_size)
end

"""
$(TYPEDEF)

Holds a tableau which defines an implicit Runge-Kutta method.
"""
mutable struct ImplicitRKTableau{MType <: AbstractMatrix, VType <: AbstractVector} <:
               ODERKTableau
    A::MType
    c::VType
    α::VType
    αEEst::VType
    stages::Int
    order::Int
    adaptiveorder::Int #The lower order of the pair. Only used for adaptivity.
end
function ImplicitRKTableau(A::MType, c::VType, α::VType, order;
        adaptiveorder = 0, αEEst = VType()) where {MType, VType}
    ImplicitRKTableau{MType, VType}(A, c, α, αEEst, length(α), order, adaptiveorder)
end
