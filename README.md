# A `--trim` case study

This example repo provides some examples how the julia 1.12 `--trim` feature can be used together with external libraries to build a executable and a C library.

It is currently WIP, but includes:

- trimmable simple CSV reader
- trimmable Nonlinear Least Squares minimization using SimpleNonlinearSolve.jl with `AutoForwardDiff`
- optimization function parameters loaded in at runtime from CSV and command line
- A variant `StaticArrays` and one with `FixedSizeArrays`

The example should also work as-is with `AutoFiniteDiff` and with an in-place objective function.

It can be compiled with something like

``` julia
julia --project=. --depwarn=error ~/.julia/juliaup/julia-1.12.0-beta4+0.x64.linux.gnu/share/julia/juliac.jl --experimental --trim=unsafe-warn --output-exe main --compile-ccallable --relative-rpath main.jl
```

*Currently JET still has a single warning, I'll get to it soon. But the parts are mostly tested to work with trimming.*
