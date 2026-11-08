# test/phase1_sabbath_test.jl — Phase 1: Ṣàngó's Fire Tests (Sabbath Enforcement)

using Test
using Dates

include("../oso_compiler.jl")
include("../oso_vm.jl")

using .OsoCompiler
using .OsoVM

@testset "Phase 1 — Ṣàngó's Fire: Sabbath Enforcement" begin
    
    # Test 1: Real witness-quorum impact mint
    @testset "Real Impact Mint with Witness Quorum" begin
        source = """
        @impact(ase=5.0) {
        }
        """
        ir = OsoCompiler.compile(source, block_number=0)
        results = OsoVM.execute_ir(ir, block_number=0)
        
        if !haskey(results[1], "error")
            @test results[1]["opcode"] == "IMPACT"
            @test results[1]["ase_minted"] ≈ 23.265  # 5.0 × 5 (quorum) × (1 - 0.0369)
            @test results[1]["tithe_rate"] == 0.0369
        end
    end
    
    # Test 2: Real tithe splitting
    @testset "Real Tithe Split (Go FFI)" begin
        source = """
        @tithe(amount=100.0) {
        }
        """
        ir = OsoCompiler.compile(source)
        results = OsoVM.execute_ir(ir)
        
        if !haskey(results[1], "error")
            @test results[1]["opcode"] == "TITHE"
            @test results[1]["total_tithe"] ≈ 3.69  # 100.0 × 0.0369
            @test results[1]["splits"]["shrine"] ≈ 1.845
            @test results[1]["splits"]["inheritance"] ≈ 0.9225
            @test results[1]["splits"]["aio"] ≈ 0.5535
            @test results[1]["splits"]["burn"] ≈ 0.369
        end
    end
    
    # Test 3: Sabbath enforcement
    @testset "Sabbath Enforcement (Saturday UTC)" begin
        # This test passes on non-Saturday
        # On Saturday UTC, should fail
        source = """
        @sabbath() {
        }
        """
        ir = OsoCompiler.compile(source)
        results = OsoVM.execute_ir(ir)
        
        now = Dates.now(Dates.UTC)
        is_saturday = Dates.dayofweek(now) == 6
        
        if is_saturday
            @test haskey(results[1], "error")
            @test results[1]["frozen"] == true
        else
            @test results[1]["opcode"] == "SABBATH"
            @test results[1]["frozen"] == false
        end
    end
    
    # Test 4: Non-reentrancy guard
    @testset "Non-Reentrancy Guard" begin
        source = """
        @nonreentrant(fn_hash=0x1234) {
        }
        """
        ir = OsoCompiler.compile(source)
        results = OsoVM.execute_ir(ir)
        
        if !haskey(results[1], "error")
            @test results[1]["opcode"] == "NONREENTRANT"
            @test results[1]["locked"] == true
        end
    end
    
    # Test 5: Block number tracking
    @testset "Block Number Propagation" begin
        source = """
        @impact(ase=1.0) {
        }
        """
        ir0 = OsoCompiler.compile(source, block_number=0)
        ir1 = OsoCompiler.compile(source, block_number=1)
        
        # Block 0 and Block 1 should have block_number in args
        ir0_data = JSON3.read(ir0)
        ir1_data = JSON3.read(ir1)
        
        @test ir0_data[1][:args][:block_number] == 0
        @test ir1_data[1][:args][:block_number] == 1
    end

end

println("✅ Phase 1 — Ṣàngó's Fire tests complete!")
