function getgensym!(defined::Dict{Symbol,Symbol}, s::Symbol)
  snew = get!(defined, s) do
    gensym(s)
  end
  snew ≢ s && (defined[snew] = snew)
  return snew
end

extractargs!(arguments::Vector{Symbol}, defined::Dict{Symbol,Symbol}, sym, mod) = nothing
# function extractargs!(arguments::Vector{Symbol}, defined::Dict{Symbol,Symbol}, sym::Symbol, mod)
#   if ((sym ∉ keys(defined)) && sym ∉ (:nothing, :(+), :(*), :(-), :(/), :(÷), :(<<), :(>>), :(>>>), :zero, :one)) && !Base.isconst(mod, sym)
#     @show getgensym!(defined, sym)
#     @assert false
#     push!(arguments, getgensym!(defined, sym))
#   end
#   nothing
# end

function _symbols(args)
  s = Vector{Symbol}(undef, length(args))
  for i in eachindex(args, s)
    s[i] = args[i]
  end
  return s
end

function define_tup!(arguments::Vector{Symbol}, defined::Dict{Symbol,Symbol}, ex::Expr, mod)
  for (i, a) ∈ enumerate(ex.args)
    if a isa Symbol
      ex.args[i] = getgensym!(defined, a)
    elseif Meta.isexpr(a, :tuple)
      define_tup!(_symbols(a.args), defined, a, mod)
    elseif Meta.isexpr(a, :ref)
      extractargs!(arguments, defined, a, mod)
    elseif Meta.isexpr(a, :parameters)
      define_tup!(_symbols(a.args), defined, a, mod)
    else
      throw("Don't know how to handle:\n $a")
    end
  end
end
function define1!(
  arguments::Vector{Symbol},
  defined::Dict{Symbol,Symbol},
  x::Vector{Any},
  mod,
)
  s = x[1]
  if s isa Symbol
    x[1] = getgensym!(defined, s)
  else
    define_tup!(arguments, defined, s::Expr, mod)
  end
end
function define_induction_variables!(
  arguments::Vector{Symbol},
  defined::Dict{Symbol,Symbol},
  ex::Expr,
  mod,
) # add `i` in `for i ∈ looprange` to `defined`
  ex.head === :for || return
  loops = ex.args[1]
  if loops.head === :block
    for loop ∈ loops.args
      define1!(arguments, defined, loop.args, mod)
    end
  else
    define1!(arguments, defined, loops.args, mod)
  end
end

function extractargs_equal!(
  arguments::Vector{Symbol},
  defined::Dict{Symbol,Symbol},
  args::Vector{Any},
  mod,
)
  arg1 = first(args)
  if arg1 isa Symbol
    args[1] = getgensym!(defined, arg1)
  elseif Meta.isexpr(arg1, :tuple)
    define_tup!(arguments, defined, arg1, mod)
  end
  nothing
end

function must_add_sym(defined::Dict{Symbol,Symbol}, arg::Symbol, mod)
  (
    (arg ∉ keys(defined)) &&
    arg ∉ (:nothing, :(+), :(*), :(-), :(/), :(÷), :(<<), :(>>), :(>>>), :zero, :one)
  ) && !Base.isconst(mod, arg)
end
function get_sym!(defined::Dict{Symbol,Symbol}, arguments::Vector{Symbol}, arg::Symbol, mod)
  if must_add_sym(defined, arg, mod)
    # @show getgensym!(defined, sym)
    # @assert false
    push!(arguments, arg)
    getgensym!(defined, arg)
  else
    get(defined, arg, arg)
  end
end
function extractargs!(
  arguments::Vector{Symbol},
  defined::Dict{Symbol,Symbol},
  expr::Expr,
  mod,
)
  define_induction_variables!(arguments, defined, expr, mod)
  head = expr.head
  args = expr.args

  startind = 1
  if head === :call
    arg1 = args[1]
    if arg1 isa Symbol && (first(string(arg1)) != '.')
      startind = isdefined(mod, arg1) ? 2 : 1
    else
      startind = 2
    end
  elseif head === :(=)
    extractargs_equal!(arguments, defined, args, mod)
  elseif head ∈ (:inbounds, :loopinfo)#, :(->))
    return
  elseif head === :(.)
    arg1 = args[1]
    if arg1 isa Symbol
      args[1] = get_sym!(defined, arguments, arg1, mod)
    else
      extractargs!(arguments, defined, arg1, mod)
    end
  elseif head === :(->)
    td = copy(defined)
    define1!(arguments::Vector{Symbol}, td, args, mod)
    extractargs!(arguments, td, args[1], mod)
    extractargs!(arguments, td, args[2], mod)
    return
  elseif head === :generator
    extractargs_equal!(arguments, defined, args[2].args, mod)
  elseif (head === :local) || (head === :global)
    for (i, arg) in enumerate(args)
      if Meta.isexpr(arg, :(=))
        extractargs_equal!(arguments, defined, arg.args, mod)
        args = arg.args
        startind = 2
      else
        args[i] = getgensym!(defined, arg)
        return
      end
    end
  elseif head === :kw
    if args[2] isa Symbol
      args[2] = get_sym!(defined, arguments, args[2], mod)
    else
      extractargs!(arguments, defined, args[2], mod)
    end
    return
  elseif head === :parameters
    for (i, arg) in enumerate(args)
      if arg isa Symbol
        sym = get_sym!(defined, arguments, arg, mod)
        args[i] = Expr(:kw, arg, sym)
      else
        extractargs!(arguments, defined, arg, mod)
      end
    end
    return
  end
  for i ∈ startind:length(args)
    argᵢ = args[i]
    (head === :ref && ((argᵢ === :end) || (argᵢ === :begin))) && continue
    if argᵢ isa Symbol
      args[i] = get_sym!(defined, arguments, argᵢ, mod)
    elseif argᵢ isa Expr
      extractargs!(arguments, defined, argᵢ, mod)
    else
      extractargs!(arguments, defined, argᵢ, mod)
    end
  end
  return
end

function symbolsubs(e::Expr, old::Symbol, new::Symbol)
  ex = Expr(e.head)
  resize!(ex.args, length(e.args))
  for i in eachindex(e.args, ex.args)
    ex.args[i] = symbolsubs(e.args[i], old, new)
  end
  return ex
end
function symbolsubs(e::Symbol, old::Symbol, new::Symbol)
  e == old ? new : e
end
symbolsubs(e, old::Symbol, new::Symbol) = e

struct NoLoop end
Base.iterate(::NoLoop) = (NoLoop(), NoLoop())
Base.iterate(::NoLoop, ::NoLoop) = nothing
@inline splitloop(x) = NoLoop(), x, CombineIndices()
struct CombineIndices end
@inline splitloop(x::AbstractRange) = NoLoop(), x, CombineIndices()
@inline function splitloop(x::CartesianIndices)
  axes = x.indices
  CartesianIndices(Base.front(axes)), last(axes), CombineIndices()
end
@inline function splitloop(x::AbstractArray)
  inds = eachindex(x)
  inner, outer = splitloop(inds)
  inner, outer, x
end
struct TupleIndices end
@inline function splitloop(x::Base.Iterators.ProductIterator{Tuple{T1,T2}}) where {T1,T2}
  iters = x.iterators
  iters[1], iters[2], TupleIndices()
end
@inline function splitloop(
  x::Base.Iterators.ProductIterator{<:Tuple{Vararg{Any,N}}},
) where {N}
  iters = x.iterators
  Base.front(iters), iters[N], TupleIndices()
end
combine(::CombineIndices, ::NoLoop, x) = x
combine(::CombineIndices, I::CartesianIndex, j) = CartesianIndex((I.I..., j))
combine(::TupleIndices, i::Tuple, j) = (i..., j)
combine(::TupleIndices, i::Number, j) = (i, j)

Base.@propagate_inbounds combine(x::AbstractArray, I, j) =
  x[combine(CombineIndices(), I, j)]
Base.@propagate_inbounds combine(x::AbstractArray, ::NoLoop, j) = x[j]

struct WrapType{T} end
wrap_type(@nospecialize(x)) = x
wrap_type(::Type{T}) where {T} = WrapType{T}()

unwrap_type(@nospecialize(x)) = x
unwrap_type(::WrapType{T}) where {T} = T

function makestatic!(expr)
  expr isa Expr || return expr
  for i in eachindex(expr.args)
    ex = expr.args[i]
    if ex isa Int
      expr.args[i] = static(ex)
    elseif ex isa Symbol
      j = findfirst(==(ex), (:axes, :size, :length))
      if j !== nothing
        expr.args[i] =
          GlobalRef(ArrayInterface, (:static_axes, :static_size, :static_length)[j])
      end
    elseif ex isa Expr
      makestatic!(ex)
    end
  end
  expr
end
function enclose(exorig::Expr, minbatchsize, per, threadlocal, reduction, stride, mod)
  Meta.isexpr(exorig, :for, 2) ||
    throw(ArgumentError("Expression invalid; should be a for loop."))
  ex = copy(exorig)
  loop_sym = Symbol("##LOOP##")
  loopstart = Symbol("##LOOPSTART##")
  loop_step = Symbol("##LOOP_STEP##")
  loop_stop = Symbol("##LOOP_STOP##")
  iter_leng = Symbol("##ITER_LENG##")
  loop_offs = Symbol("##LOOPOFFSET##")
  innerloop = Symbol("##inner##loop##")
  rcombiner = Symbol("##split##recombined##")
  reduction_op, reduction_var = reduction
  threadlocal_var = Symbol("threadlocal")
  #FIXME: don't do this?
  per = stride ? :thread : per
  # arguments = Symbol[]#loop_offs, loop_step]
  arguments = Symbol[innerloop, rcombiner]#loop_offs, loop_step]
  defined = Dict{Symbol,Symbol}(loop_offs => loop_offs, loop_step => loop_step)
  threadlocal_var_gen = getgensym!(defined, threadlocal_var)
  reduction_var_gen = Expr(:tuple)
  if reduction_var !== Tuple{}()
    for i ∈ eachindex(reduction_var)
      push!(reduction_var_gen.args, getgensym!(defined, reduction_var[i]))
    end
  end
  define_induction_variables!(arguments, defined, ex, mod)
  firstloop = ex.args[1]
  if firstloop.head === :block
    secondaryloopsargs = firstloop.args[2:end]
    firstloop = firstloop.args[1]
  else
    secondaryloopsargs = Any[]
  end
  loop = firstloop.args[2]
  # @show ex loop
  body = ex.args[2]
  if length(secondaryloopsargs) == 1
    body = Expr(:for, only(secondaryloopsargs), body)
  elseif length(secondaryloopsargs) > 1
    sl = Expr(:block)
    append!(sl.args, secondaryloopsargs)
    body = Expr(:for, sl, body)
  end
  fla1 = firstloop.args[1]
  excomb = if fla1 isa Symbol
    fla1 = getgensym!(defined, fla1)
    quote
      # for $(firstloop.args[1]) in
      var"##outer##"::Int = Int($loopstart)::Int
      while var"##outer##" <= $loop_stop
        for var"##inner##" in $innerloop
          $fla1 = $combine($rcombiner, var"##inner##", var"##outer##")
          $body
        end
        var"##outer##" += var"##STEP##"
      end
    end
  else
    @assert fla1 isa Expr
    for i in eachindex(fla1.args)
      fla1.args[i] = getgensym!(defined, fla1.args[i])
    end
    quote
      # for $(firstloop.args[1]) in
      var"##outer##"::Int = Int($loopstart)::Int
      while var"##outer##" <= $loop_stop
        for var"##inner##" in $innerloop
          $fla1 = $combine($rcombiner, var"##inner##", var"##outer##")
          $body
        end
        var"##outer##" += var"##STEP##"
      end
    end
  end
  if ex.args[1].head === :block
    for i ∈ 2:length(ex.args[1].args)
      extractargs!(arguments, defined, ex.args[1].args[i], mod)
    end
  end
  for i ∈ 2:length(ex.args)
    extractargs!(arguments, defined, ex.args[i], mod)
  end
  # @show ex.args[1] firstloop body
  # if length(ex.args[
  # ex = quote
  #   # for $(firstloop.args[1]) in
  #   for var"##outer##" in $firstlooprange, var"##inner##" in $innerloop
  #     $(firstloop.args[1]) = $combine($rcombiner, var"##inner##", var"##outer##")
  #     $body
  #   end
  # end
  # typexpr_incomplete is missing `funcs`
  # outerloop = Symbol("##outer##")
  num_thread_expr::Union{Symbol,Expr} = if per === :core
    Expr(:call, min, Symbol("##NUM#THREADS##"), Expr(:call, Threads.nthreads()))
  else
    Symbol("##NUM#THREADS##")
  end

  iter_len_def = quote
    $(esc(innerloop)), $loop_sym, $(esc(rcombiner)) = $splitloop($(esc(makestatic!(loop))))
    $iter_leng = $static_length($loop_sym)
  end

  q = quote
    var"##NUM#THREADS#TO#USE##" = $num_thread_expr
    $(stride ? nothing : iter_len_def)
    $loop_step = $static_step($loop_sym)
    $loop_offs = $static_first($loop_sym)
  end
  threadtup = Expr(:tuple, iter_leng)
  if minbatchsize isa Integer && minbatchsize ≤ 1
    push!(threadtup.args, :(min($iter_leng, var"##NUM#THREADS#TO#USE##")))
  else
    il = :(div(
      $iter_leng,
      $(minbatchsize isa Int ? StaticInt(minbatchsize) : esc(minbatchsize)),
    ))
    push!(threadtup.args, :(min($il, $num_thread_expr)))
  end
  closure = Symbol("##closure##")
  donothing = Expr(:block)
  return_quote = Expr(:return)
  # threadlocal stuff
  threadlocal_var_single = gensym(threadlocal_var)
  threadlocal_val, threadlocal_type = threadlocal
  q_single =
    threadlocal_val === Symbol("") ? exorig :
    symbolsubs(exorig, threadlocal_var, threadlocal_var_single)
  # threadlocal_type = getfield(mod, threadlocal_type)
  threadlocal_accum = Symbol("##THREADLOCAL##ACCUM##")
  threadlocal_init_single =
    threadlocal_val === Symbol("") ? donothing :
    :($threadlocal_var_single = $threadlocal_val)
  threadlocal_return_single =
    threadlocal_val === Symbol("") ? donothing : :($threadlocal_var_single)
  threadlocal_vect_single =
    threadlocal_val === Symbol("") ? donothing :
    :($(esc(threadlocal_var)) = [single_thread_result])
  threadlocal_init =
    threadlocal_val === Symbol("") ? donothing :
    quote
      $(esc(threadlocal_accum)) =
        Vector{$threadlocal_type}(undef, max(1, $(threadtup.args[2])))
    end
  threadlocal_vect =
    threadlocal_val === Symbol("") ? donothing :
    :($(esc(threadlocal_var)) = multi_thread_result)
  threadlocal_get =
    threadlocal_val === Symbol("") ? donothing :
    :($threadlocal_var_gen::$threadlocal_type = $threadlocal_val)
  threadlocal_set =
    threadlocal_val === Symbol("") ? donothing :
    :($threadlocal_accum[var"##THREAD##"] = $threadlocal_var_gen)
  threadlocal_return = threadlocal_val === Symbol("") ? donothing : :($threadlocal_accum)
  threadlocal_val !== Symbol("") && push!(q.args, threadlocal_init)
  # reduction stuff
  reduction_ops = Expr(:tuple)
  reduction_vars = Expr(:tuple)
  reduction_inits = Expr(:tuple)
  reduction_set = Expr(:block)
  for i in eachindex(reduction_var)
    op = getfield(Polyester, reduction_op[i])
    var = esc(reduction_var[i])
    init = :(initializer($op, $var))
    push!(reduction_ops.args, op)
    push!(reduction_vars.args, var)
    push!(reduction_inits.args, init)
    push!(reduction_set.args, :($var = $op($var, reduction_final[$i])))
  end
  reduction_init =
    reduction_var === Tuple{}() ? donothing :
    :($reduction_var_gen = var"##REDUCTION##INIT##")
  if reduction_var !== Tuple{}()
    push!(return_quote.args, reduction_var_gen)
  else
    push!(return_quote.args, nothing)
  end

  args = Expr(:tuple, Symbol("##LOOPOFFSET##"), Symbol("##LOOP_STEP##"))
  closure_args = Expr(:tuple, args, :(var"##SUBSTART##"::Int), :(var"##SUBSTOP##"::Int))
  if threadlocal_val !== Symbol("") || stride
    push!(closure_args.args, :(var"##THREAD##"::Int))
  end
  reduction_var !== Tuple{}() && push!(closure_args.args, Symbol("##REDUCTION##INIT##"))
  if stride
    # we are to do length(var"##SUBSTART##":var"##SUBSTOP##") iterations
    loop_start_expr =
      :(var"##THREAD##" * var"##LOOP_STEP##" + var"##LOOPOFFSET##" - var"##LOOP_STEP##")
    loop_stop_expr = :($loopstart + (var"##SUBSTOP##" - var"##SUBSTART##") * var"##STEP##")
  else
    loop_start_expr =
      :(var"##SUBSTART##" * var"##LOOP_STEP##" + var"##LOOPOFFSET##" - var"##LOOP_STEP##")
    loop_stop_expr =
      :(var"##SUBSTOP##" * var"##LOOP_STEP##" + var"##LOOPOFFSET##" - var"##LOOP_STEP##")
  end
  unwrap_args = Expr(:block)
  closureq = quote
    $closure = let
      @inline $closure_args -> begin
        $unwrap_args
        local var"##STEP##" = $(
          stride ?
          :($loop_step * min(Threads.nthreads()::Int, Sys.CPU_THREADS::Int)) :
          loop_step
        )
        local $loopstart = $loop_start_expr
        local $loop_stop = $loop_stop_expr
        # $(stride ? :(@show $loopstart, $loop_stop) : nothing)
        $threadlocal_get
        $reduction_init
        @inbounds begin
          $excomb
        end
        $threadlocal_set
        $return_quote
      end
    end
  end
  push!(q.args, esc(closureq))
  batchcall = if threadlocal_val !== Symbol("") || stride
    Expr(
      :call,
      batch,
      esc(closure),
      Val(true),
      reduction_ops,
      reduction_inits,
      threadtup,
      Symbol("##LOOPOFFSET##"),
      Symbol("##LOOP_STEP##"),
    )
  else
    Expr(
      :call,
      batch,
      esc(closure),
      Val(false),
      reduction_ops,
      reduction_inits,
      threadtup,
      Symbol("##LOOPOFFSET##"),
      Symbol("##LOOP_STEP##"),
    )
  end
  for a ∈ arguments
    push!(args.args, get(defined, a, a))
    push!(batchcall.args, :($wrap_type($(esc(a)))))
  end
  if threadlocal_val !== Symbol("")
    push!(args.args, threadlocal_accum)
    push!(batchcall.args, esc(threadlocal_accum))
  end
  for a in args.args
    push!(unwrap_args.args, :($a = $unwrap_type($a)))
  end
  push!(q.args, batchcall)
  quote
    var"##NUM#THREADS##" = $(Threads.nthreads)()
    $(stride ? iter_len_def : nothing)
    if (
      $(
        stride ? :((var"##NUM#THREADS##" == 1) || (var"##NUM#THREADS##" > $iter_leng)) :
        :(var"##NUM#THREADS##" == 1)
      )
    )
      single_thread_result = begin
        $(esc(threadlocal_init_single)) # Initialize threadlocal storage
        $(esc(q_single))
        $(esc(threadlocal_return_single))
      end
      $threadlocal_vect_single
    else
      multi_thread_result = let
        reduction_final = $q
        $reduction_set
        $(esc(threadlocal_return))
      end
      $threadlocal_vect
    end
    nothing
  end
end

"""
    @batch for i in Iter; ...; end

Evaluate the loop on multiple threads. The execution of the loop waits for the evaluation
of all iterations.

    @batch minbatch=N for i in Iter; ...; end

Evaluate at least N iterations per thread. Will use at most `length(Iter) ÷ N` threads.

    @batch threadlocal=init() for i in Iter; ...; end

Create a thread-local storage used in the loop.

The `init` function will be called at the start at each thread. `threadlocal` will
refer to storage local for the thread. At the end of the loop, a `threadlocal`
vector containing all the thread-local values will be available. A type can be specified
with `threadlocal=init()::Type`.

    @batch reduction=((op1, var1), (op2, var2), ...) for i in Iter; ...; end

Perform OpenMP-esque reduction on the `isbits` variables `var1`, `var2`, `...` using the
operations `op1`, `op2`, `...` . The variables have to be initialized before the loop and
cannot be a fieldname like `x.y` or `x[i]`.
Supported operations are `+`, `*`, `min`, `max`, `&`, and `|`. The type does not have
to be provided, since it is already inferred from the initialized variables---**caution has
to be taken to ensure that the type remains consistent throughout the loop**.
While `threadlocal` can do the same thing, `reduction` does not incur additional allocations
and is generally more efficient for its purpose. It is up to the user to ensure that there
are no data dependencies between iterations, which could lead to incorrect results.

    @batch per=core for i in Iter; ...; end
    @batch per=thread for i in Iter; ...; end

Use at most 1 thread per physical core, or 1 thread per CPU thread, respectively.
One thread per core will mean less threads competing for the cache, while (for example) if
there are two hardware threads per physical core, then using each thread means that there
are two independent instruction streams feeding the CPU's execution units. When one of
these streams isn't enough to make the most of out of order execution, this could increase
total throughput.

Which performs better will depend on the workload, so if you're not sure it may be worth
benchmarking both.

LoopVectorization.jl currently only uses up to 1 thread per physical core. Because there
is some overhead to switching the number of threads used, `per=core` is `@batch`'s default,
so that `Polyester.@batch` and `LoopVectorization.@tturbo` work well together by default.

Threads are not pinned to a given CPU core and the total number of available threads is
still governed by `--threads` or `JULIA_NUM_THREADS`.

You can pass both `per=(core/thread)` and `minbatch=N` options at the same time, e.g.

    @batch per=thread minbatch=2000 for i in Iter; ...; end
    @batch minbatch=5000 per=core   for i in Iter; ...; end

    @batch stride=true for i in Iter; ...; end

This may be better for load balancing if iterations close to each other take a similar
amount of time, but iterations far apart take different lengths of time. Setting this also
forces `per=thread`. The default is `stride=false`.
"""
macro batch(ex)
  enclose(
    macroexpand(__module__, ex),
    1,
    :unspecified,
    (Symbol(""), :Any), # threadlocal: var, type
    (Tuple{}(), Tuple{}()), # reduction: ops, vars
    false,
    __module__,
  )
end
function interpret_kwarg(
  arg,
  minbatch = 1,
  per = :unspecified,
  threadlocal = (Symbol(""), :Any), # var, type
  reduction = (Tuple{}(), Tuple{}()), # ops, vars
  stride = false,
)
  a = arg.args[1]
  v = arg.args[2]
  if a === :minbatch
    minbatch = v
  elseif a === :per
    per = v::Symbol
    @assert (per === :core) | (per === :thread)
  elseif a === :reduction
    @assert Meta.isexpr(v, :tuple) && v.head == :tuple
    if Meta.isexpr(v.args[1], :tuple, 2)
      for red in v.args
        @assert Meta.isexpr(red, :tuple, 2) && red.head == :tuple
      end
      reducops = ntuple(length(v.args)) do i
        v.args[i].args[1]
      end
      @assert SUPPORTED_REDUCE_OPS ⊇ reducops "Unsupported reduction operation."
      reducvars = ntuple(length(v.args)) do i
        v.args[i].args[2]
      end
      @assert allunique(reducvars)
      reduction = (reducops, reducvars)
    else
      reduction = ((v.args[1],), (v.args[2],))
    end
  elseif a === :threadlocal
    if Meta.isexpr(v, :(::), 2) && v.head == :(::)
      threadlocal = (v.args[1], v.args[2])
    else
      threadlocal = (v, :Any)
    end
  elseif a === :stride
    stride = v::Bool
  else
    throw(ArgumentError("kwarg $(a) not recognized."))
  end
  minbatch, per, threadlocal, reduction, stride
end
macro batch(arg1, ex)
  minbatch, per, threadlocal, reduction, stride = interpret_kwarg(arg1)
  per = per === :unspecified ? (stride ? :thread : :core) : per
  enclose(
    macroexpand(__module__, ex),
    minbatch,
    per,
    threadlocal,
    reduction,
    stride,
    __module__,
  )
end
macro batch(arg1, arg2, ex)
  minbatch, per, threadlocal, reduction, stride = interpret_kwarg(arg1)
  minbatch, per, threadlocal, reduction, stride =
    interpret_kwarg(arg2, minbatch, per, threadlocal, reduction, stride)
  per = per === :unspecified ? (stride ? :thread : :core) : per
  enclose(
    macroexpand(__module__, ex),
    minbatch,
    per,
    threadlocal,
    reduction,
    stride,
    __module__,
  )
end
macro batch(arg1, arg2, arg3, ex)
  minbatch, per, threadlocal, reduction, stride = interpret_kwarg(arg1)
  minbatch, per, threadlocal, reduction, stride =
    interpret_kwarg(arg2, minbatch, per, threadlocal, reduction, stride)
  minbatch, per, threadlocal, reduction, stride =
    interpret_kwarg(arg3, minbatch, per, threadlocal, reduction, stride)
  per = per === :unspecified ? (stride ? :thread : :core) : per
  enclose(
    macroexpand(__module__, ex),
    minbatch,
    per,
    threadlocal,
    reduction,
    stride,
    __module__,
  )
end
macro batch(arg1, arg2, arg3, arg4, ex)
  minbatch, per, threadlocal, reduction, stride = interpret_kwarg(arg1)
  minbatch, per, threadlocal, reduction, stride =
    interpret_kwarg(arg2, minbatch, per, threadlocal, reduction, stride)
  minbatch, per, threadlocal, reduction, stride =
    interpret_kwarg(arg3, minbatch, per, threadlocal, reduction, stride)
  minbatch, per, threadlocal, reduction, stride =
    interpret_kwarg(arg4, minbatch, per, threadlocal, reduction, stride)
  per = per === :unspecified ? (stride ? :thread : :core) : per
  enclose(
    macroexpand(__module__, ex),
    minbatch,
    per,
    threadlocal,
    reduction,
    stride,
    __module__,
  )
end
macro batch(arg1, arg2, arg3, arg4, arg5, ex)
  minbatch, per, threadlocal, reduction, stride = interpret_kwarg(arg1)
  minbatch, per, threadlocal, reduction, stride =
    interpret_kwarg(arg2, minbatch, per, threadlocal, reduction, stride)
  minbatch, per, threadlocal, reduction, stride =
    interpret_kwarg(arg3, minbatch, per, threadlocal, reduction, stride)
  minbatch, per, threadlocal, reduction, stride =
    interpret_kwarg(arg4, minbatch, per, threadlocal, reduction, stride)
  minbatch, per, threadlocal, reduction, stride =
    interpret_kwarg(arg5, minbatch, per, threadlocal, reduction, stride)
  per = per === :unspecified ? (stride ? :thread : :core) : per
  enclose(
    macroexpand(__module__, ex),
    minbatch,
    per,
    threadlocal,
    reduction,
    stride,
    __module__,
  )
end
