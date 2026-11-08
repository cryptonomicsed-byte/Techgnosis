# compiler_spec_test.jl — the compiler is a function of OPCODE_SPEC.toml.
using Test
include(joinpath(@__DIR__, "..", "oso_compiler.jl"))
using .OsoCompiler
using JSON3, TOML

const SPEC = TOML.parsefile(joinpath(@__DIR__, "..", "spec", "OPCODE_SPEC.toml"))
byte(name) = parse(Int, only(o["byte"] for o in SPEC["opcode"] if name in o["names"])[3:end], base = 16)
ir(src; kw...) = JSON3.read(OsoCompiler.compile(src; kw...))
fails(src, needle) = try
        OsoCompiler.compile(src); false
    catch e
        e isa OsoCompiler.CompileError && occursin(needle, sprint(showerror, e))
    end

@testset "bound attributes compile to the VM's own bytes" begin
    @test ir("@tithe(amount=100.0) { split }")[1]["opcode"] == byte("TITHE")
    @test ir("@biponSeed(path=\"m/0\") { }")[1]["opcode"] == byte("BIPON_SEED")
    @test ir("@veil(category=\"ode\") { run }")[1]["opcode"] == byte("VEIL")
    @test ir("@nonreentrant() { }")[1]["opcode"] == byte("NONREENTRANT")
    @test ir("@genesisFlawToken(token=\"ASHE\") { }")[1]["opcode"] == byte("GENESIS_FLAW_TOKEN")
    # the specific collisions the plan named are gone
    @test ir("@veil() { }")[1]["opcode"] != byte("GENESIS_FLAW_TOKEN")   # was a mint
    @test ir("@nonreentrant() { }")[1]["opcode"] != byte("REQUIRE")
end

@testset "fail closed" begin
    @test fails("@tihte(amount=1) { }", "not a bound attribute")        # the typo case
    @test fails("@ritual(x=1) { }", "not a bound attribute")            # unbound, not 0x00
    @test fails("@sabbath() { }", "temporal gate")                      # not an opcode
    @test fails("@impact(ase=5.0) { }", "deleted")                      # deleted mint
    @test fails("just some prose, no attributes", "empty program")      # was [] silently
    @test fails("@tithe(amount=1)", "malformed attribute")              # missing braces
    @test fails("@tithe(amount) { }", "malformed argument")
    # one bad attribute rejects the whole program; nothing partial is emitted
    @test fails("@tithe(amount=1) { } @tihte(amount=1) { }", "@tihte")
end

@testset "no opcode literal lives in the compiler (plan R3)" begin
    src = read(joinpath(@__DIR__, "..", "oso_compiler.jl"), String)
    code = join(filter(l -> !startswith(strip(l), "#"), split(src, '\n')), '\n')
    @test !occursin(r"0x[0-9a-fA-F]{2}\b", code)
end

@testset "vendored spec matches OSOVM's, when OSOVM is checked out alongside" begin
    upstream = joinpath(@__DIR__, "..", "..", "OSOVM", "OPCODE_SPEC.toml")
    if isfile(upstream)
        @test read(upstream, String) == read(joinpath(@__DIR__, "..", "spec", "OPCODE_SPEC.toml"), String)
    else
        @test_skip "OSOVM not checked out next to Techgnosis"
    end
end

@testset "primitives are macro-expansions over opcodes (plan 2.4)" begin
    b = ir("@birth(name=\"oracle-7\") { }")
    @test [x["opcode"] for x in b] == byte.(["BIPON_SEED", "GENESIS_FLAW_TOKEN", "AGENT_BIRTH", "RECEIPT"])
    @test all(x["args"]["name"] == "oracle-7" for x in b)
    # gates that do not exist make the primitive refuse, never compile around them
    @test fails("@think(intent=\"x\") { }", "HERMETIC_GATE")
    @test fails("@act(op=\"tithe\") { }", "CAPABILITY_CHECK")
end
