# test/techgnosis_vm_test.jl — OSO VM Tests

using Test

include("../techgnosis_compiler.jl")
include("../techgnosis_vm.jl")

using .OsoCompiler
using .OsoVM

@testset "OSO Compiler + VM" begin
    # Test 1: Basic @impact
    source1 = """
    @impact(ase=5.0) {
    }
    """
    ir1 = OsoCompiler.compile(source1)
    results1 = OsoVM.execute_ir(ir1)
    @test results1[1]["opcode"] == "IMPACT"
    @test results1[1]["ase_minted"] ≈ 23.265  # 5.0 × 5 witnesses × (1 - 0.0369)
    
    # Test 2: @tithe
    source2 = """
    @tithe(rate=0.0369) {
    }
    """
    ir2 = OsoCompiler.compile(source2)
    results2 = OsoVM.execute_ir(ir2)
    @test results2[1]["opcode"] == "TITHE"
    
    # Test 3: @merkleRoot
    source3 = """
    @merkleRoot(hash="0xabc123") {
    }
    """
    ir3 = OsoCompiler.compile(source3)
    results3 = OsoVM.execute_ir(ir3)
    @test results3[1]["opcode"] == "MERKLE_ROOT"
    @test results3[1]["hash"] == "0xabc123"
    
    # Test 4: @sabbath (mock Saturday)
    source4 = """
    @sabbath() {
    }
    """
    ir4 = OsoCompiler.compile(source4)
    results4 = OsoVM.execute_ir(ir4)
    @test results4[1]["opcode"] == "SABBATH"

    # Test 5: @veil (VEIL opcode 0x2b — PID simulation via VeilSim)
    source5 = """
    @veil(veil_id=1, kp=0.1, ki=0.01, kd=0.05) {
    }
    """
    ir5 = OsoCompiler.compile(source5)
    results5 = OsoVM.execute_ir(ir5)
    @test results5[1]["opcode"] == "VEIL"
    @test haskey(results5[1], "f1_score")
    @test haskey(results5[1], "ase_minted")
    @test haskey(results5[1], "veil_id")
    @test 0.0 ≤ results5[1]["f1_score"] ≤ 1.0
    @test results5[1]["ase_minted"] ∈ [0.0, 2.5, 5.0]
end

println("✅ All OSO tests passed!")
