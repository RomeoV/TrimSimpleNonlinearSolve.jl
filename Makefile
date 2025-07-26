main: src/TrimSimpleNonlinearSolve.jl main.jl
	julia --project=. --depwarn=error ~/.julia/juliaup/julia-1.12.0-rc1+0.x64.linux.gnu/share/julia/juliac/juliac.jl --experimental --trim=unsafe-warn --output-exe main --compile-ccallable main.jl
