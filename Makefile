main: src/TrimSimpleNonlinearSolve.jl main.jl
	JULIAC=$$(julia -e 'print(normpath(joinpath(Sys.BINDIR, Base.DATAROOTDIR, "julia", "juliac", "juliac.jl")))' 2>/dev/null || echo "") ; \
	if [ -z "$$JULIAC" ] || [ ! -f "$$JULIAC" ]; then \
		echo "Error: juliac.jl not found" ; \
		exit 1 ; \
	fi ; \
	julia --project=. -e 'using Pkg; Pkg.instantiate()' ; \
	julia --project=. --depwarn=error "$$JULIAC" --experimental --trim=unsafe-warn --output-exe main --compile-ccallable main.jl
