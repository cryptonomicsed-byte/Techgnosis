# Legacy tests — kept for history, not run

These assert the v1 compiler's private byte table. All three were **already
failing on the untouched v1 compiler** (2026-11-08):

- `oso_vm_test.jl` cannot load: it includes `techgnosis_compiler.jl`, which does not exist.
- `phase1_sabbath_test.jl` asserts `@impact` mints `ase_minted ≈ 23.265`, computed from
  the caller's own `ase=` and witness count — a caller-priced Àṣẹ mint, the I-12/I-13
  violation OSOVM deleted — and treats `@sabbath` as an opcode.
- `phase2_genesis_flaw_test.jl` asserts a repeatable genesis mint.

The compiler now resolves bytes from `spec/OPCODE_SPEC.toml` and fails closed;
see `test/compiler_spec_test.jl`.
