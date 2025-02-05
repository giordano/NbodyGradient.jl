# Transit structures
abstract type TransitOutput{T} <: AbstractOutput{T} end

"""

Holds the transit times and derivatives.
"""
struct TransitTiming{T<:AbstractFloat} <: TransitOutput{T}
    tt::Matrix{T}
    dtdq0::Array{T,4}
    dtdelements::Array{T,4}
    count::Vector{Int64}
    ntt::Int64
    ti::Int64
    occs::Vector{Int64}
    dtdq::Array{T,3}
    gsave::Vector{T}
    s_prior::State{T}
    s_transit::State{T}
end

function TransitTiming(tmax,ic::ElementsIC{T},ti::Int64=1) where T<:AbstractFloat
    n = ic.nbody
    ind = isfinite.(tmax./ic.elements[:,2])
    ntt = maximum(ceil.(Int64,abs.(tmax./ic.elements[ind,2])).+3)
    tt = zeros(T,n,ntt)
    dtdq0 = zeros(T,n,ntt,7,n)
    dtdelements = zeros(T,n,ntt,7,n)
    count = zeros(Int64,n)
    occs = setdiff(collect(1:n),ti)
    dtdq = zeros(T,1,7,n)
    gsave = zeros(T,n)
    s_prior = State(ic)
    s_transit = State(ic)
    return TransitTiming(tt,dtdq0,dtdelements,count,ntt,ti,occs,dtdq,gsave,s_prior,s_transit)
end

"""

Structure for transit timing, impact parameter, and sky velocity
"""
struct TransitParameters{T<:AbstractFloat} <: TransitOutput{T}
    ttbv::Array{T,3}
    dtbvdq0::Array{T,5}
    dtbvdelements::Array{T,5}
    count::Vector{Int64}
    ntt::Int64
    ti::Int64
    occs::Vector{Int64}
    dtbvdq::Array{T,3}
    gsave::Vector{T}
    s_prior::State{T}
    s_transit::State{T}
end

function TransitParameters(tmax,ic::ElementsIC{T},ti::Int64=1) where T<:AbstractFloat
    n = ic.nbody
    ind = isfinite.(tmax./ic.elements[:,2])
    ntt = maximum(ceil.(Int64,abs.(tmax./ic.elements[ind,2])).+3)
    ttbv = zeros(T,3,n,ntt)
    dtbvdq0 = zeros(T,3,n,ntt,7,n)
    dtbvdelements = zeros(T,3,n,ntt,7,n)
    count = zeros(Int64,n)
    occs = setdiff(collect(1:n),ti)
    dtbvdq = zeros(T,3,7,n)
    gsave = zeros(T,n)
    s_prior = State(ic)
    s_transit = State(ic)
    return TransitParameters(ttbv,dtbvdq0,dtbvdelements,count,ntt,ti,occs,dtbvdq,gsave,s_prior,s_transit)
end

struct TransitSnapshot{T<:AbstractFloat} <: TransitOutput{T}
    nt::Int64
    times::Vector{T}
    bsky2::Matrix{T}
    vsky::Matrix{T}
    dbvdq0::Array{T,5}
    dbvdelements::Array{T,5}
end

function TransitSnapshot(times::Vector{T},ic::ElementsIC{T}) where T<:AbstractFloat
    n = ic.nbody
    nt = length(times)
    return TransitSeries(nt,times,zeros(T,n,nt),zeros(T,n,nt),zeros(T,2,n,nt,7,n),zeros(T,2,n,nt,7,n))
end

function zero_out!(tt::TransitOutput{T}) where T
    for i in 1:length(fieldnames(typeof(tt)))
        if typeof(getfield(tt,i)) <: Array{T}
            getfield(tt,i) .= zero(T)
        end
    end
    tt.count .= 0
end

"""

Main integrator method for Transit calculations.
"""
function (intr::Integrator)(s::State{T}, tt::TransitOutput{T}; grad::Bool=true) where T<:AbstractFloat
    # Allocate structures
    d = Derivatives(T, s.n)

    t0 = s.t[1] # Initial time
    nsteps = abs(round(Int64,intr.tmax/intr.h))
    h = intr.h * check_step(t0, intr.tmax+t0) # get direction of integration

    for i in tt.occs
        # Compute the relative sky velocity dotted with position:
        tt.gsave[i] = g!(i,tt.ti,s.x,s.v)
    end

    istep = 0
    for _ in 1:nsteps

        # Take an integration step
        if grad
            intr.scheme(s,d,h)
        else
            intr.scheme(s,h)
        end
        istep += 1
        s.t[1] = t0 + (istep * h)

        # Check if a transit occured; record time.
        detect_transits!(s,d,tt,intr,grad=grad)
    end
    # Calculate derivatives
    if grad
        calc_dtdelements!(s,tt)
    end
end

"""

Integrator method for outputting `TransitSnapshot`.
"""
function (intr::Integrator)(s::State{T},ts::TransitSnapshot{T};grad::Bool=true) where T<:AbstractFloat
    # Integrate to, and output b and v_sky for each body, for a list of times.
    # Should be sorted times.
    # NOTE: Need to fix so that if initial time is a 0, s.dqdt isn't 0s.
    if grad; dbvdq = zeros(T,2,7,s.n); end

    # Integrate to each time, using intr.h, and output b and vsky (only want primary transits for now)
    t0 = s.t[1]
    for (j,ti) in enumerate(ts.times)
        intr(s,ti;grad=grad)
        for i in 2:s.n
            if grad
                ts.vsky[i,j],ts.bsky2[i,j] = calc_dbvdq!(s,dbvdq,1,i)
                for ibv=1:2, k=1:7, p=1:s.n
                    ts.dbvdq0[ibv,i,j,k,p] = dbvdq[ibv,k,p]
                end
            else
                ts.vsky[i,j],ts.bsky2[i,j] = calc_bv(s,1,i)
            end
        end
        # Step to the next full time step, as measured from t0.
        #steps = round(Int64 ,(s.t[1] - t0) / intr.h, RoundUp)
        #intr(s,t0 + (steps * intr.h); grad=grad)
    end
    calc_dbvdelements!(s,ts)
    return
end

# Includes for source
files = ["timing.jl","snapshot.jl"]
include.(files)