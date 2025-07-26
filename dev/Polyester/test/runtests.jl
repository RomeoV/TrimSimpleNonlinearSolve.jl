println(
  "Starting tests with $(Threads.nthreads()) threads out of `Sys.CPU_THREADS = $(Sys.CPU_THREADS)`...",
)
using Polyester, Aqua, ForwardDiff
using PolyesterWeave: dynamic_thread_count # min(Sys.CPU_THREADS, Threads.nthreads())
using Base.Threads: @threads
using Test

function bsin!(y, x, r = eachindex(y, x))
  @batch for i ∈ r
    y[i] = sin(x[i])
  end
  return y
end
function bsin_stride!(y, x, r = eachindex(y, x))
  @batch stride = true for i ∈ r
    y[i] = sin(x[i])
  end
  return y
end
function bcos!(y, x)
  @batch per = core for i ∈ eachindex(y, x)
    local cxᵢ
    cxᵢ = cos.(x[i])
    y[i] = cxᵢ
  end
  return y
end
myindices(x) = 1:length(x) # test hygiene, issue #11
function sin_batch_sum(v)
  s = zeros(8, Threads.nthreads())
  @batch minbatch = 10 for i in myindices(v)
    s[1, Threads.threadid()] += sin(v[i])
  end
  if cld(length(v), 10) < Threads.nthreads()
    @test s[1, end] == 0.0
  end
  return sum(view(s, 1, :))
end
function rowsum_batch!(x, A)
  @batch for n ∈ axes(A, 2)
    local s = 0.0
    @simd for m ∈ axes(A, 1)
      s += A[m, n]
    end
    x[n] = s
  end
end
function bar!(dest, src)
  @batch for i in eachindex(dest)
    dest[i] = src.a.b[i]
  end
  dest
end

function rangemap!(f::F, allargs, start, stop) where {F}
  dest = first(allargs)
  args = Base.tail(allargs)
  @inbounds @simd for i ∈ start:stop
    dest[i] = f(Base.unsafe_getindex.(args, i)...)
  end
  nothing
end

function tmap!(f::F, args::Vararg{AbstractArray,K}) where {K,F}
  dest = first(args)
  N = length(dest)
  mapfun! = (allargs, start, stop) -> rangemap!(f, allargs, start, stop)
  batch(mapfun!, (N, Int(Threads.nthreads())), args...)
  dest
end
function issue15!(dest, src)
  @batch for i in eachindex(src)
    dest.src[i] = src[i]
  end
  dest
end
function issue16!(dest)
  @batch for i = 2:1
    dest[i] = i
  end
  true
end
function issue17!(dest)
  @assert size(dest, 1) == 5
  @batch for j in axes(dest, 2)
    x = ntuple(i -> i * j, Val(5)) # works if this line is commented out
    for i in axes(dest, 1)
      dest[i, j] = i * j
    end
  end
end
function issue18!(dest)
  @assert length(dest) == 3
  @assert dest[1] == 1
  @batch for i = 2:3
    dest[i] = i
  end
  @test dest ≈ 1:3
end

function issue25!(dest, x, y)
  @batch for (i, j) ∈ Iterators.product(eachindex(x), eachindex(y))
    dest[i, j] = x[i, begin] * y[j, end]
  end
  dest
end
function issue25_but_with_strides!(dest, x, y)
  @batch stride = true for (i, j) ∈ Iterators.product(eachindex(x), eachindex(y))
    dest[i, j] = x[i, begin] * y[j, end]
  end
  dest
end

function issue108!(y::Vector{T1}, x::Vector{T2}) where {T1,T2}
  @batch for i in eachindex(y)
    y[i] = sum(x[j] for j = 2i-oneunit(i):2i)
  end
end

function issue108_comment!(data::Vector{T}, functions) where {T}
  @batch for i in eachindex(data)
    for f in functions
      data[i] += f(data[i])
    end
  end
end

function issue116!(y::Vector{T}, x::Vector{T}) where {T}
  @batch for i = 1:length(x)
    y[i] = exp(x[i] + one(T))
  end
end


@testset "Range Map" begin

  x = rand(1024)
  y = rand(length(x))
  z = similar(x)
  foo(x, y) = exp(-0.5abs2(x - y))
  println("Running `tmap!` test...")
  @test tmap!(foo, z, x, y) ≈ foo.(x, y)

  function slow_task!((x, digits, n), j, k)
    start = 1 + (n * (j - 1)) ÷ Threads.nthreads()
    stop = (n * k) ÷ Threads.nthreads()
    target = 0.0
    for i ∈ start:stop
      target += occursin(digits, string(i)) ? 0.0 : 1.0 / i
    end
    x[1, j] = target
  end

  function slow_cheap(n, digits)
    x = zeros(8, Int(Threads.nthreads()))
    batch(slow_task!, (Threads.nthreads(), Threads.nthreads()), x, digits, n)
    sum(@view(x[1, 1:end]))
  end

  function slow_single_thread(n, digits)
    target = 0.0
    for i ∈ 1:n
      target += occursin(digits, string(i)) ? 0.0 : 1.0 / i
    end
    return target
  end

  @test slow_cheap(1000, "9") ≈ slow_single_thread(1000, "9")

  x = randn(100_000)
  y = similar(x)
  z = similar(y)
  @test bsin!(y, x) == (z .= sin.(x))
  fill!(y, NaN)
  @test bsin_stride!(y, x) == z
  @test bcos!(y, x) == (z .= cos.(x))
  @views z[1:3:length(x)] .= sin.(x[1:3:length(x)])
  @test bsin!(y, x, 1:3:length(x)) == z
  @test sum(sin, x) ≈ sin_batch_sum(x)
  @test sum(sin, 1:9) ≈ sin_batch_sum(1:9)

  A = rand(200, 300)
  x = Vector{Float64}(undef, 300)
  rowsum_batch!(x, A)
  @test x ≈ vec(sum(A, dims = 1))

  let dest = zeros(10^3), src = (; a = (; b = rand(length(dest))))
    @test bar!(dest, src) == src.a.b
  end
  let src = rand(100), dest = (; src = similar(src))
    @test issue15!(dest, src).src == src
    @test issue16!(dest)
  end
  let dest = zeros(5, 10_000)
    issue17!(dest)
    @test dest == axes(dest, 1) .* axes(dest, 2)'
  end
  issue18!(ones(3))

  let x = rand(100), y = rand(100), dest1 = x .* y'
    dest0 = similar(dest1)
    # TODO: don't only thread outer
    @test issue25!(dest0, x, y) ≈ dest1
    fill!(dest0, NaN)
    @test issue25_but_with_strides!(dest0, x, y) ≈ dest1
  end
end

@testset "start and stop values" begin
  println("Running start and stop values tests...")
  function record_start_stop!((start_indices, end_indices), start, stop)
    start_indices[Threads.threadid()] = start
    end_indices[Threads.threadid()] = stop
    sleep(1) # if task completes two quickly, the mainthread will start stealing work back.
  end

  start_indices = zeros(Int, dynamic_thread_count())
  end_indices = zeros(Int, dynamic_thread_count())

  for range in [Threads.nthreads(), dynamic_thread_count(), 1000, 1001]
    start_indices .= 0
    end_indices .= 0
    batch(record_start_stop!, (range, dynamic_thread_count()), start_indices, end_indices)
    indices_test_per_thread = end_indices .- start_indices .+ 1
    acceptable_no_per_thread =
      [fld(range, dynamic_thread_count()), cld(range, dynamic_thread_count())]
    @test all(in.(indices_test_per_thread, Ref(acceptable_no_per_thread)))
    @test sum(indices_test_per_thread) == range
    @test length(unique(start_indices)) == dynamic_thread_count()
    @test length(unique(end_indices)) == dynamic_thread_count()
  end
end

@testset "!isbits args" begin
  println("Running !isbits args test...")
  # Struct and string
  mutable struct TestStruct
    vec::Vector{String}
  end
  vec_length = 20
  ts = TestStruct(["init" for i = 1:vec_length])
  update_text!((ts, val), start, stop) = ts.vec[start:stop] .= val
  batch(update_text!, (vec_length, Threads.nthreads()), ts, "new_val")
  @test all(ts.vec .== "new_val")


  struct Issue20
    values::Vector{Float64}
  end

  function issue20!(dest, cache)
    @batch for i in eachindex(dest)
      factor = -cache.a.values[i]
      dest[i] *= factor
    end
  end

  dest = ones(20)
  cache = (; a = Issue20(ones(length(dest))))
  issue20!(dest, cache)
  @test all(dest .≈ -1)
end

@testset "Non-UnitRange loops" begin
  u = randn(10, 100)
  x = view(u, 1:5, :)
  xref = 2 .* x
  @batch for i in eachindex(x)
    x[i] *= 2.0
  end
  arrayofarrays = collect(eachcol(x))
  @batch for x in arrayofarrays
    x .*= 2.0
  end
  @test reduce(hcat, arrayofarrays) == (xref .*= 2)
end

@testset "Generators and looping over array of functions" begin
  x = collect(1:12)
  y = zeros(6)
  issue108!(y, x)
  @test y == [sum(x[j] for j = 2i-oneunit(i):2i) for i = 1:6]

  functions = [x -> n * x for n = 1:3]
  data = rand(100)
  data1 = deepcopy(data)
  issue108_comment!(data, functions)
  for i in eachindex(data1)
    for f in functions
      data1[i] += f(data1[i])
    end
  end
  @test data == data1
end

println("Issue 245...")

import Polyester: splitloop, combine, NoLoop, @batch
using Test

struct LazyTree{T}
  t::T
end

Base.getindex(lt::LazyTree, row::Int) = lt.t[row]
Base.length(lt::LazyTree) = length(lt.t)
Base.lastindex(lt::LazyTree) = length(lt)
Base.eachindex(lt::LazyTree) = 1:lastindex(lt)
splitloop(e::Base.Iterators.Enumerate{LazyTree{T}}) where {T} =
  NoLoop(), eachindex(e.itr), e
combine(e::Iterators.Enumerate{LazyTree{T}}, ::NoLoop, j) where {T} = @inbounds e[j]
Base.getindex(e::Iterators.Enumerate{LazyTree{T}}, row::Int) where {T} =
  (row, first(iterate(e.itr, row)))
function Base.iterate(tree::LazyTree, idx = 1)
  idx > length(tree) && return nothing
  return tree.t[idx], idx + 1
end
Base.firstindex(e::Iterators.Enumerate{LazyTree{T}}) where {T} = firstindex(e.itr)
Base.lastindex(e::Iterators.Enumerate{LazyTree{T}}) where {T} = lastindex(e.itr)
Base.eachindex(e::Iterators.Enumerate{LazyTree{T}}) where {T} = eachindex(e.itr)

@testset "unROOT Enumerate interface" begin
  t = LazyTree(collect(2001:3000))
  for i = 1:3
    println("ITER $i")
    inds = [Vector{Int}() for _ = 1:Threads.nthreads()]
    @batch for (i, evt) in enumerate(t)
      push!(inds[Threads.threadid()], i)
    end
    @test sum([
      length(inds[i] ∩ inds[j]) for i = 1:length(inds), j = 1:length(inds) if j > i
    ]) == 0
  end
  evt = 5
end

@testset "not-specializing-on-type heuristics" begin
  allocated(f::F, args...) where {F} = @allocated f(args...)
  x = rand(10000)
  y = similar(x)
  allocated(issue116!, y, x)
  @test y ≈ exp.(x .+ 1.0)
  @test allocated(issue116!, y, x) == 0
end

@testset "threadlocal storage" begin
  local1 = let
    @batch threadlocal = 0 for i = 0:9
      threadlocal += 1
    end
    sum(threadlocal)
  end
  local2 = let
    @batch minbatch = 5 threadlocal = 0 for i = 0:9
      threadlocal += 1
    end
    sum(threadlocal)
  end
  local3 = let
    @batch per = core threadlocal = 0 for i = 0:9
      threadlocal += 1
    end
    sum(threadlocal)
  end
  local4 = let
    @batch per = core minbatch = 100 threadlocal = 0 for i = 0:9
      threadlocal += 1
    end
    sum(threadlocal)
  end
  myinitA() = 0
  local5 = let
    @batch threadlocal = myinitA() for i = 0:9
      threadlocal += 1
    end
    sum(threadlocal)
  end
  myinitB() = [0]
  local6 = let
    @batch threadlocal = myinitB() for i = 0:9
      threadlocal .+= 1
    end
    sum(threadlocal)[1]
  end
  @test local1 == local2 == local3 == local4 == local5 == local6
  # check that each thread has a separate init
  inits = let
    @batch threadlocal = rand() for i = 0:9
      threadlocal += 1
    end
    threadlocal
  end
  @test length(inits) == 1 || inits[1] != inits[end]
  # check that types are respected
  myinitD() = Float16(1.0)
  settingtype = let
    @batch threadlocal = myinitD()::Float16 for i = 0:9
      threadlocal += 1
    end
    threadlocal
  end
  @test eltype(settingtype) == Float16
  settingabstype = let
    @batch threadlocal = myinitD()::AbstractFloat for i = 0:9
      threadlocal += 1
    end
    threadlocal
  end
  @test eltype(settingabstype) <: AbstractFloat
  # check for excessive allocations
  function f()
    n = 1000
    @batch minbatch = 10 threadlocal = 1.0::Float64 for i = 1:n
      threadlocal += 1.0 / threadlocal
    end
    return threadlocal
  end
  allocated(f::F) where {F} = @allocated f()
  allocated(f)
  @test allocated(f) < 300 + 40 * Threads.nthreads()
end

@testset "reduction" begin
  local1 = let
    red = 0
    @batch reduction = (+, red) for i = 0:9
      red += 1
    end
    red
  end
  local2 = let
    red = 0
    @batch minbatch = 5 reduction = (+, red) for i = 0:9
      red += 1
    end
    red
  end
  local3 = let
    red = 0
    @batch per = core reduction = (+, red) for i = 0:9
      red += 1
    end
    red
  end
  local4 = let
    red = 0
    @batch per = core minbatch = 100 reduction = (+, red) for i = 0:9
      red += 1
    end
    red
  end
  local5 = let
    red = 0
    @batch minbatch = 100 stride = true reduction = (+, red) for i = 0:9
      red += 1
    end
    red
  end
  myinitA() = 0
  local6 = let
    red = myinitA()
    @batch reduction = (+, red) for i = 0:9
      red += 1
    end
    red
  end
  local7, local8 = let
    red = 0
    @batch minbatch = 100 stride = true reduction = (+, red) threadlocal = red for i = 0:9
      red += 1
      threadlocal += 1
    end
    red, threadlocal[1]
  end
  localsr = let # stride + reduction w/o minbatch
    red = 0
    @batch stride = true reduction = (+, red) for i = 0:9
      red += 1
    end
    red
  end
  @test local1 ==
        local2 ==
        local3 ==
        local4 ==
        local5 ==
        local6 ==
        local7 ==
        local8 ==
        localsr
  # check different operations
  local9 = let
    red = 1.0
    @batch reduction = (*, red) for i = 1:100
      red *= 4i^2 / (4i^2 - 1)
    end
    2red
  end
  @test local9 ≈ 2prod(4i^2 / (4i^2 - 1) for i = 1:100)
  # multiple reductions
  local10, local11, local12 = let
    red1 = 0
    red2 = 0
    red3 = 0
    @batch reduction = ((+, red1), (+, red2), (+, red3)) for i = 0:9
      red1 += 1
      red2 += 1
      red3 -= 1
    end
    red1, red2, red3
  end
  @test local10 == local11 == -local12
  # check for name interference with threadlocal (used to error on single threaded runs)
  function f()
    n = 1000
    threadlocal = 0
    @batch minbatch = 10 reduction = (+, threadlocal) for i = 1:n
      threadlocal += 1
    end
    return threadlocal
  end
  allocated(f::F) where {F} = @allocated f()
  inferred(f::F) where {F} =
    try
      @inferred f()
      true
    catch
      false
    end
  allocated(f)
  @test allocated(f) == 0
  @test inferred(f) == true
  # remaining supported operations
  arr = rand(10)
  local13, local14, local15, local16 = let arr = arr
    red1 = true
    red2 = false
    red3 = typemax(eltype(arr))
    red4 = typemin(eltype(arr))
    @batch reduction = ((&, red1), (|, red2), (min, red3), (max, red4)) for x in arr
      red1 &= x > 0.5
      red2 |= x > 0.5
      red3 = min(red3, x)
      red4 = max(red4, x)
    end
    red1, red2, red3, red4
  end
  @test (local13, local14, local15, local16) == (
    mapreduce(x -> x > 0.5, &, arr),
    mapreduce(x -> x > 0.5, |, arr),
    minimum(arr),
    maximum(arr),
  )
end

@testset "locks and refvalues" begin
  a = Ref(0.0)
  l = Threads.SpinLock()
  @time @batch for i = 1:1_000
    lock(l)
    try
      a[] += i
    finally
      unlock(l)
    end
  end
  @test a[] == sum(1:1_000)
end

@testset "gensym" begin
  # issue 59 (lack of gensym for keyword arguments)
  function f(; kw = 10)
    kw
  end
  buf = [0, 0]
  @batch for i = 1:2
    buf[i] = f(; kw = i)
  end
  @test buf == [1, 2]
  # issue 61
  function ff(buf, a)
    @batch for i = 1:2
      buf[i] = f(kw = i + a)
    end
  end
  ff(buf, 2)
  @test buf == [3, 4]
end

@testset "tuple and keywork unpacking" begin
  # issue 75
  buf = (1, (2, 3))
  dest = zeros(Int, 3)
  @batch for i = 1:2
    (a, (b, c)) = buf
    dest .= [a, b, c]
  end
  @test dest == [1, 2, 3]
end

@testset "gensym keywords with implicit name" begin
  # issue 78 (lack of support for keyword arguments using only variable names without `=`)

  f(a; b = 10.0, c = 100.0) = a + b + c

  buf = [0, 0]
  b = 0.0

  Threads.nthreads() == 1 && println("the issue arises only on multithreading runs")

  @batch for i = 1:2
    buf[i] = f(i; b, c = 0.0)
  end

  @test buf == [1, 2]
end

@testset "disable_polyester_threads" begin
  function inner(x, y, j)
    for i ∈ axes(x, 1)
      y[i, j] = sin(x[i, j])
    end
  end

  function inner_polyester(x, y, j)
    @batch for i ∈ axes(x, 1)
      y[i, j] = sin(x[i, j])
    end
  end

  function inner_thread(x, y, j)
    @threads for i ∈ axes(x, 1)
      y[i, j] = sin(x[i, j])
    end
  end

  function sequential_sequential(x, y)
    for j ∈ axes(x, 2)
      inner(x, y, j)
    end
  end

  function sequential_polyester(x, y)
    for j ∈ axes(x, 2)
      inner_polyester(x, y, j)
    end
  end

  function sequential_thread(x, y)
    for j ∈ axes(x, 2)
      inner_thread(x, y, j)
    end
  end

  function threads_of_polyester(x, y)
    @threads for j ∈ axes(x, 2)
      inner_polyester(x, y, j)
    end
  end

  function threads_of_polyester_inner_disable(x, y)
    @threads for j ∈ axes(x, 2)
      Polyester.disable_polyester_threads() do
        inner_polyester(x, y, j)
      end
    end
  end

  function threads_of_thread(x, y)
    @threads for j ∈ axes(x, 2)
      inner_thread(x, y, j)
    end
  end

  function threads_of_sequential(x, y)
    @threads for j ∈ axes(x, 2)
      inner(x, y, j)
    end
  end

  y = rand(10, 10) # (size of inner problem, size of outer problem)
  x = rand(size(y)...)
  inner(x, y, 1)
  good_y = copy(y)
  inner_polyester(x, y, 1)
  @assert good_y == y
  inner_thread(x, y, 1)
  @assert good_y == y
  sequential_sequential(x, y)
  good_y = copy(y)
  sequential_polyester(x, y)
  @assert good_y == y
  sequential_thread(x, y)
  @assert good_y == y
  threads_of_polyester(x, y)
  @assert good_y == y
  threads_of_polyester_inner_disable(x, y)
  @assert good_y == y
  disable_polyester_threads() do
    threads_of_polyester(x, y)
  end
  @assert good_y == y
  threads_of_sequential(x, y)
  @assert good_y == y
  threads_of_thread(x, y)
  @assert good_y == y
end

@testset "reset_threads!" begin
  sys_threads::Int = (Sys.CPU_THREADS)::Int
  runs_on_ci = parse(Bool, get(ENV, "GITHUB_ACTIONS", "false"))
  num_threads = min(Threads.nthreads(), sys_threads)

  function issue30_set!(dst)
    @batch per = thread for i in eachindex(dst)
      dst[i] = Threads.threadid()
    end
    return dst
  end

  dst = zeros(Int, 2 * max(num_threads, Threads.nthreads(), (Sys.CPU_THREADS)::Int))
  @test_nowarn issue30_set!(dst)
  if !(runs_on_ci && (Int == Int32))
    # There are issues on x86 systems in GitHub actions I don't understand
    @test sort!(unique(dst)) == 1:num_threads
  end

  function issue30_throw!(dst)
    @batch per = thread for i in eachindex(dst)
      dst[i] = Threads.threadid()
      if i > 1
        throw(DomainError("expected error"))
      end
    end
    return dst
  end

  # After throwing an error, the current implementation
  # disables multithreading
  @test_throws DomainError issue30_throw!(dst)
  @test_nowarn issue30_set!(dst)
  if dynamic_thread_count() <= num_threads
    @test sort!(unique(dst)) == 1:1
  end

  # Multithreading works again after resetting the threads
  @test_nowarn Polyester.reset_threads!()
  @test_nowarn issue30_set!(dst)
  if !(runs_on_ci && (Int == Int32))
    # There are issues on x86 systems in GitHub actions I don't understand
    @test sort!(unique(dst)) == 1:num_threads
  end
end

@testset "issue #119" begin
  # https://github.com/JuliaSIMD/Polyester.jl/issues/119
  function find_call_to_nthreads(expr)
    expr isa Expr || return false
    if expr.head === :call
      if Base.Threads.nthreads in expr.args
        return true
      end
    end
    return any(find_call_to_nthreads, expr.args)
  end

  expr = @macroexpand @batch for i = 1:100
    a[i] = i
  end

  @test find_call_to_nthreads(expr)
end


function dummy_broadcast!(x)
  @batch for i = 1:2
    a = (1,) .+ (1,)
    x[i] = only(a)
  end
end
let x = Vector{Float64}(undef, 2)
  dummy_broadcast!(x)
  @test x == fill(2.0, 2)
end

if VERSION ≥ v"1.6"
  println("Package tests complete. Running `Aqua` checks.")
  Aqua.test_all(Polyester; deps_compat = (check_extras = false,))
end
