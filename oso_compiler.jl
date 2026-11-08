# oso_compiler.jl — Techgnosis -> OSOVM IR compiler (v2, fail closed)
# Bínò ÈL Guà — Crown Architect
# Ọbàtálá — Master Auditor
#
# What changed from v1, and why:
#
#   v1 kept its own attribute -> byte table. 25 of its 27 entries meant
#   something else in OSOVM (@sabbath -> NONREENTRANT, @veil ->
#   GENESIS_FLAW_TOKEN, a mint; @impact -> a byte deleted for being a
#   caller-priced mint). An unknown attribute only warned and compiled to 0x00,
#   which is HALT. A file with no attributes compiled to [] silently.
#
#   v2 contains no opcode literals at all. An attribute binds to an OSOVM opcode
#   NAME (spec/TECHGNOSIS_BINDINGS.toml); the name resolves to a byte through
#   OPCODE_SPEC.toml, which OSOVM generates from its live VM. Everything that
#   cannot be resolved -- an unknown attribute, an unbound one, a name the VM
#   does not dispatch -- is a compile error. An empty program is a compile error.
#
# Public API is unchanged: compile(source; block_number) -> JSON IR.

module OsoCompiler

using JSON3
using TOML

const SPEC_DIR = joinpath(@__DIR__, "spec")

struct CompileError <: Exception
    msg::String
end
Base.showerror(io::IO, e::CompileError) = print(io, "Techgnosis compile error: ", e.msg)

struct Instruction
    opcode::UInt8
    args::Dict{Symbol, Any}
end

struct Attribute
    type::Symbol
    args::Dict{Symbol, Any}
    line::Int
end

struct Ritual
    name::String
    attributes::Vector{Attribute}
end

struct AST
    rituals::Vector{Ritual}
end

# ===== SPEC: the only source of bytes =====

struct Spec
    byte_of::Dict{String, UInt8}          # opcode name -> byte (dispatched only)
    status_of::Dict{String, String}       # opcode name -> status (all declared)
    bind::Dict{Symbol, String}            # attribute -> opcode name
    not_an_opcode::Dict{Symbol, String}   # attribute -> why it is not an instruction
    macros::Dict{Symbol, Dict{String, Any}}  # primitive -> {steps, requires, domain}
end

function load_spec(; opcode_spec::AbstractString = get(ENV, "OSOVM_OPCODE_SPEC",
                                                       joinpath(SPEC_DIR, "OPCODE_SPEC.toml")),
                     bindings::AbstractString = joinpath(SPEC_DIR, "TECHGNOSIS_BINDINGS.toml"))::Spec
    ops = TOML.parsefile(opcode_spec)
    byte_of, status_of = Dict{String,UInt8}(), Dict{String,String}()
    for op in ops["opcode"]
        b = parse(UInt8, op["byte"][3:end], base = 16)
        for n in op["names"]
            status_of[n] = op["status"]
            op["status"] == "dispatched" && (byte_of[n] = b)
        end
    end
    bt = TOML.parsefile(bindings)
    bind = Dict(Symbol(k) => String(v) for (k, v) in get(bt, "bind", Dict()))
    nao  = Dict(Symbol(k) => String(v) for (k, v) in get(bt, "not_an_opcode", Dict()))
    macros = Dict(Symbol(k) => Dict{String,Any}(v) for (k, v) in get(bt, "macro", Dict()))
    for (prim, m) in macros, step in get(m, "steps", String[])
        get(status_of, step, "") == "dispatched" || throw(CompileError(
            "macro $prim: step $step is '$(get(status_of, step, "not in OPCODE_SPEC.toml"))', not dispatched"))
    end
    # A binding must point at something the VM actually runs -- checked at load,
    # so a stale binding fails every compile rather than one program at runtime.
    for (attr, name) in bind
        st = get(status_of, name, nothing)
        st === nothing && throw(CompileError("binding @$attr -> $name: no such opcode in OPCODE_SPEC.toml"))
        st == "dispatched" || throw(CompileError("binding @$attr -> $name: opcode is '$st', not dispatched"))
    end
    return Spec(byte_of, status_of, bind, nao, macros)
end

const _SPEC = Ref{Union{Spec, Nothing}}(nothing)
function spec()::Spec
    _SPEC[] === nothing && (_SPEC[] = load_spec())
    return _SPEC[]
end

# Kept for callers that list the surface; derived, never hand-maintained.
CORE_ATTRIBUTES() = sort!(collect(keys(spec().bind)))

# ===== PARSER =====

const RITUAL_RE = r"(@[\wùÙ]+)\s*\(([^)]*)\)\s*\{([^}]*)\}"s
const STRAY_ATTR_RE = r"@[\wùÙ]+"

function parse_oso(source::AbstractString)::AST
    rituals = Ritual[]
    covered = falses(ncodeunits(source))
    for m in eachmatch(RITUAL_RE, source)
        attr_name = Symbol(m.captures[1][2:end])  # strip @
        line = count(==('\n'), SubString(source, 1, prevind(source, m.offset))) + 1
        push!(rituals, Ritual(String(attr_name),
                              [Attribute(attr_name, parse_args(m.captures[2]), line)]))
        covered[m.offset:m.offset + ncodeunits(m.match) - 1] .= true
    end
    # An @attribute the ritual pattern did not consume is malformed (missing
    # parens or braces). v1 dropped it silently; that is how a typo vanished.
    for m in eachmatch(STRAY_ATTR_RE, source)
        covered[m.offset] && continue
        line = count(==('\n'), SubString(source, 1, prevind(source, m.offset))) + 1
        throw(CompileError("line $line: malformed attribute $(m.match) -- expected $(m.match)(args) { ... }"))
    end
    isempty(rituals) && throw(CompileError("no attributes found: an empty program is not a program"))
    return AST(rituals)
end

function parse_args(args_str::AbstractString)::Dict{Symbol, Any}
    args = Dict{Symbol, Any}()
    isempty(strip(args_str)) && return args
    for pair in split(args_str, ",")
        parts = split(strip(pair), "=")
        length(parts) == 2 || throw(CompileError("malformed argument '$(strip(pair))' -- expected key=value"))
        key = Symbol(strip(parts[1]))
        val = strip(parts[2], ['"', ' '])
        if occursin(r"^-?\d+\.\d+$", val)
            args[key] = parse(Float64, val)
        elseif occursin(r"^-?\d+$", val)
            args[key] = parse(Int64, val)
        else
            args[key] = String(val)  # strings and 0x... hex stay strings
        end
    end
    return args
end

# ===== VALIDATOR: fail closed =====

function resolve(attr::Attribute, s::Spec = spec())::UInt8
    t = attr.type
    haskey(s.not_an_opcode, t) && throw(CompileError("line $(attr.line): @$t -- $(s.not_an_opcode[t])"))
    name = get(s.bind, t, nothing)
    name === nothing && throw(CompileError(
        "line $(attr.line): @$t is not a bound attribute. Bound: " *
        join(("@" .* string.(sort!(collect(keys(s.bind))))), ", ")))
    return s.byte_of[name]   # load_spec guaranteed it is dispatched
end

# A primitive expands to several instructions; a bound attribute to one.
function expand(attr::Attribute, s::Spec = spec())::Vector{UInt8}
    m = get(s.macros, attr.type, nothing)
    m === nothing && return [resolve(attr, s)]
    missing_gates = [g for g in get(m, "requires", String[]) if !haskey(s.byte_of, g)]
    isempty(missing_gates) || throw(CompileError(
        "line $(attr.line): @$(attr.type) requires $(join(missing_gates, ", ")), which the VM does not " *
        "implement. A primitive that skips its gate would let a program authorise its own action."))
    bytes = UInt8[]
    for g in get(m, "requires", String[]); push!(bytes, s.byte_of[g]); end   # gates run first
    if get(m, "domain", false)
        op = get(attr.args, :op, nothing)
        op === nothing && throw(CompileError("line $(attr.line): @$(attr.type) needs op=<attribute>"))
        push!(bytes, resolve(Attribute(Symbol(op), Dict{Symbol,Any}(), attr.line), s))
    end
    append!(bytes, (s.byte_of[n] for n in m["steps"]))
    return bytes
end

validate_ast(ast::AST)::Nothing = (foreach(r -> foreach(expand, r.attributes), ast.rituals); nothing)

# ===== IR EMITTER =====

function emit_ir(ast::AST; block_number::Int = 0)::Vector{Instruction}
    instructions = Instruction[]
    for ritual in ast.rituals, attr in ritual.attributes
        args = copy(attr.args)
        args[:block_number] = block_number
        for b in expand(attr)
            push!(instructions, Instruction(b, copy(args)))
        end
    end
    return instructions
end

# ===== PUBLIC API =====

function compile(source::AbstractString; block_number::Int = 0)::String
    ast = parse_oso(source)
    validate_ast(ast)
    ir = emit_ir(ast; block_number = block_number)
    return JSON3.write([Dict("opcode" => Int(i.opcode), "args" => i.args) for i in ir])
end

export compile, CompileError

end  # module OsoCompiler
