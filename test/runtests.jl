using Pkg
Pkg.activate("ReTest")
Pkg.develop(PackageSpec(path="../InlineTest"))

using ReTest

module M
using ReTest

RUN = []

@testset "a" begin
    push!(RUN, "a")
    @test true
end

@testset "b$i" for i=1:2
    push!(RUN, "b$i")
    @test true
end

@testset "c" begin
    push!(RUN, "c")
    @test true

    @testset "d" begin
        push!(RUN, "d")
        @test true
    end

    @testset "e$i" for i=1:2
        push!(RUN, "e$i")
        @test true
    end
end

@testset "f$i" for i=1:1
    push!(RUN, "f$i")
    @test true

    @testset "g" begin
        push!(RUN, "g")
        @test true
    end

    @testset "h$i" for i=1:2
        push!(RUN, "h$i")
        @test true
    end
end

innertestsets = ["d", "e1", "e2", "g", "h1", "h2"]

function check(rx, list)
    empty!(RUN)
    retest(M, Regex(rx))
    @test RUN == list
    mktemp() do path, io
        redirect_stdout(io) do
            retest(M, Regex(rx), dry=true)
        end
        seekstart(io)
        expected = map(list) do t
            if t in innertestsets
                "  " * t
            else
                t
            end
        end
        @test readchomp(io) == join(expected, '\n')
    end
end
end

# we don't put these checks in a @testset, as this would modify filtering logic
# (e.g. with `@testset "filtering" ...`, testset subjects would start with "/filtering/...")
using .M: check
check("a", ["a"])
check("a1", []) # testset is "final", so we do a full match
check("b", ["b1", "b2"])
check("/b", ["b1", "b2"])
check("b1", ["b1"])
check("c1", []) # "c1" is *not* partially matched against "/c/"
check("c/1", []) # "c" is partially matched, but nothing fully matches afterwards
check("c/d1", [])
check("c/d", ["c", "d"])
check("/c", ["c", "d", "e1", "e2"])
check(".*d", ["c", "d"])
check(".*(e1|e2)", ["c", "e1", "e2"])
check("f1", ["f1", "g", "h1", "h2"])
check("f",  ["f1", "g", "h1", "h2"])
check(".*g", ["f1", "g"])
check(".*h", ["f1", "h1", "h2"])
check(".*h1", ["f1", "h1"])
check(".*h\$", [])

# by default, respect order of tests:
check("", ["a", "b1", "b2", "c", "d", "e1", "e2", "f1", "g", "h1", "h2"])
retest(M)

module N
using ReTest

RUN = []

# testing non-final non-toplevel testsets
@testset "i" begin
    push!(RUN, "i")
    @test true

    @testset "j" begin
        push!(RUN, "j")
        @test true

        @testset "k" begin
            push!(RUN, "k")
            @test true
        end
    end

    @testset "l$i" for i=1:1
        push!(RUN, "l$i")
        @test true

        @testset "m" begin
            push!(RUN, "m")
            @test true
        end
    end
end

function check(rx, list)
    empty!(RUN)
    retest(N, Regex(rx))
    @test sort(RUN) == sort(list)
    empty!(RUN)
    N.runtests(Regex(rx))
    @test sort(RUN) == sort(list)
end
end

import .N
N.check(".*j1", [])
N.check(".*j/1", [])
N.check("^/i/j0", [])
N.check("^/i/l10", [])

module P
using ReTest

RUN = []

# testing non-final non-toplevel testsets
@testset "a" begin
    push!(RUN, "a")
    @test true

    @testset "b" begin
        push!(RUN, "b")
        @test true
    end

    @testset "b|c" begin
        push!(RUN, "b|c")
        @test true
    end
end

@testset "D&E" begin
    push!(RUN, "D&E")
    @test true
end

function check(rx, list)
    empty!(RUN)
    retest(P, rx)
    @test sort(RUN) == sort(list)
    empty!(RUN)
    P.runtests(rx)
    @test sort(RUN) == sort(list)
end
end

import .P # test ReTest's wrapping of non-regex patterns
P.check("b", ["a", "b", "b|c"]) # an implicit prefix r".*" is added
P.check("B", ["a", "b", "b|c"]) # idem, case-insensitive
P.check(r"B", []) # not case-insensitive

if VERSION >= v"1.3"
    P.check("b|c", ["a", "b|c"]) # "b" is not matched
    P.check("B|C", ["a", "b|c"]) # idem, case-insensitive
end

P.check("d&e", ["D&E"])
P.check("d&E", ["D&E"])
P.check(r"d&E", [])
P.check(r"d&E"i, ["D&E"])


RUN = []
@testset "toplevel" begin
    # this tests that the testset is run exactly once
    # Main is special here, as it's both in Base.loaded_modules
    # and it gets registered automatically in ReTest.TESTED_MODULES
    push!(RUN, "toplevel")
    @test true
end

retest()
retest("a", shuffle=true, stats=true)
retest(M, N, P, "b", dry=true)
@test_throws ArgumentError retest("A", r"b")

@test RUN == ["toplevel"]

retest(r"^/f1") # just test that a regex can be passed

module Loops1
using ReTest

RUN = []

@testset "loops 1" begin
    a = 1
    b = 2

    @testset "local$i" for i in (a, b)
        push!(RUN, i)
        @test true
        @testset "sub" begin
            push!(RUN, 0)
            @test true

            @testset "final" begin
                @test true
                push!(RUN, -1)
            end
        end
    end
end
end

@test_logs (:warn, r"could not evaluate testset-for iterator.*") retest(Loops1, r"asd")
@test Loops1.RUN == [1, 0, 2, 0]
empty!(Loops1.RUN)
retest(Loops1) # should not log
@test Loops1.RUN == [1, 0, -1, 2, 0, -1]

module Loops2
using ReTest

RUN = []

@testset "loops 2" begin
    @testset "generator $i $I" for (i, I) in (i => typeof(i) for i in (1, 2))
        push!(RUN, i)
        @test true
        @testset "sub" begin
            push!(RUN, 0)
            @test true

            @testset "final" begin
                @test true
                push!(RUN, -1)
            end
        end
    end
end
end

@test_logs (:warn, r"could not evaluate testset-for iterator.*") retest(Loops2, r"asd")
@test Loops2.RUN == [1, 0, 2, 0]
empty!(Loops2.RUN)
retest(Loops2)
@test Loops2.RUN == [1, 0, -1, 2, 0, -1]

module Loops3
using ReTest

RUN = []

@testset "loops 3" begin
    @testset "generator $i $I" for (i, I) in [i => typeof(i) for i in (1, 2)]
        push!(RUN, i)
        @test true
        @testset "sub" begin
            push!(RUN, 0)
            @test true

            @testset "final" begin
                @test true
                push!(RUN, -1)
            end
        end
    end
end
end

retest(Loops3, r"asd")
@test Loops3.RUN == []
empty!(Loops3.RUN)
retest(Loops3)
@test Loops3.RUN == [1, 0, -1, 2, 0, -1]

### Failing ##################################################################

module Failing
using ReTest

@testset "has fails" begin
    @test false
end
end

@test_throws Test.TestSetException retest(Failing)

### InlineTest ###############################################################

using Pkg
Pkg.activate("./FakePackage")
Pkg.develop(PackageSpec(path="../InlineTest"))
Pkg.develop("ReTest")
Pkg.test("FakePackage")
