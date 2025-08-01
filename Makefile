main: src/TrimSimpleNonlinearSolve.jl main.jl
	JULIAC=$$(julia -e 'print(normpath(joinpath(Sys.BINDIR, Base.DATAROOTDIR, "julia", "juliac", "juliac.jl")))' 2>/dev/null || echo "") ; \
	julia --project=. --depwarn=error "$$JULIAC" --experimental --trim=unsafe-warn --output-exe main main.jl
