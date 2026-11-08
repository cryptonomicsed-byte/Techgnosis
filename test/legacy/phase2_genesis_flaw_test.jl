# test/phase2_genesis_flaw_test.jl — Phase 2: Èṣù's Twist (Genesis Flaw Tests)

using Test
using JSON3

include("../oso_compiler.jl")
include("../oso_vm.jl")

using .OsoCompiler
using .OsoVM

@testset "Phase 2 — Èṣù's Twist: Genesis Flaw" begin
    
    # Test 1: Block 0 with ASHE token mints
    @testset "Block 0: ASHE Token Mints (Flaw Activated)" begin
        source = """
        @genesisFlawToken(token="ASHE", amount=1.0) {
        }
        """
        ir = OsoCompiler.compile(source, block_number=0)
        results = OsoVM.execute_ir(ir, block_number=0)
        
        @test results[1]["genesis"] == true
        @test results[1]["amount"] == 1.0
        @test results[1]["token_minted"] == "Àṣẹ"
        @test results[1]["original_token"] == "ASHE"
        @test results[1]["transformation"] == "misspelling → precision"
    end
    
    # Test 2: Block > 0 with ASHE token rejected
    @testset "Block 1: ASHE Token Rejected (Flaw Denied)" begin
        source = """
        @genesisFlawToken(token="ASHE", amount=1.0) {
        }
        """
        ir = OsoCompiler.compile(source, block_number=1)
        results = OsoVM.execute_ir(ir, block_number=1)
        
        @test results[1]["genesis"] == false
        @test results[1]["error"] == "flaw_denied_post_genesis"
        @test results[1]["rejected_token"] == "ASHE"
    end
    
    # Test 3: Block > 0 with correct Àṣẹ token accepted
    @testset "Block 1: Correct Àṣẹ Token Accepted" begin
        source = """
        @genesisFlawToken(token="Àṣẹ", amount=1.0) {
        }
        """
        ir = OsoCompiler.compile(source, block_number=1)
        results = OsoVM.execute_ir(ir, block_number=1)
        
        # Should mint with correct token
        if !haskey(results[1], "error")
            @test results[1]["genesis"] == false
        end
    end
    
    # Test 4: Block 0 without ASHE token fails
    @testset "Block 0: Non-ASHE Token Rejected at Genesis" begin
        source = """
        @genesisFlawToken(token="Àṣẹ", amount=1.0) {
        }
        """
        ir = OsoCompiler.compile(source, block_number=0)
        results = OsoVM.execute_ir(ir, block_number=0)
        
        @test results[1]["error"] == "only_ASHE_mints_on_block_0"
    end

end

println("✅ Phase 2 — Èṣù's Twist tests complete!")
