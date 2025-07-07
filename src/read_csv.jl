module TrimmableCSV
using StructArrays
using Moshi
import Moshi.Match: @match

maybeparse(T::Type{<:Number}, x) = parse(T, x)
maybeparse(T::Type{<:AbstractString}, x) = string(x)

function parse_data(buf::IOBuffer, rowtype = @NamedTuple{a::Int, b::Int, c::String})
    coltypes = tuple(rowtype.types...)
    rows = rowtype[]
    for row in split(read(buf, String), '\n')
        @match row begin
            "" => nothing
            str::AbstractString => let fields = split(str, ','), coltypes=coltypes
                tpl = ntuple(length(coltypes)) do i
                     maybeparse(coltypes[i], fields[i])
                end
                push!(rows, tpl)
            end
            _ => nothing
        end
    end
    df = StructArray(rows)
end

function main(inputfile::String="data2.csv")
    data = read(inputfile, String)
    df = parse_data(IOBuffer(data))
    println(Core.stdout, sum(df.a))
    return sum(df.a)
end

Base.@ccallable function main(argc::Cint, argv::Ptr{Ptr{Int8}})::Cint
    cstr = unsafe_load(argv, 2)
    inputfile = unsafe_string(cstr)
    println(Core.stdout, inputfile)
    main(inputfile)
    return 0
end
Base.Experimental.entrypoint(main, (Cint, Ptr{Ptr{UInt8}}))
end
