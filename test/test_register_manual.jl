using T4ARegistrator
using Test
using LibGit2
using TOML

@testset "register_manual" begin
    # Create a temporary test package directory
    test_pkg_dir = mktempdir()
    atexit(() -> rm(test_pkg_dir; recursive=true, force=true))
    
    # Create a minimal Project.toml
    test_pkg_name = "TestPkgManual"
    test_uuid = "87654321-4321-4321-4321-210987654321"
    test_version = "0.1.0"
    
    mkdir(joinpath(test_pkg_dir, "src"))
    open(joinpath(test_pkg_dir, "Project.toml"), "w") do io
        println(io, "name = \"$(test_pkg_name)\"")
        println(io, "uuid = \"$(test_uuid)\"")
        println(io, "version = \"$(test_version)\"")
    end
    
    # Create minimal src file
    open(joinpath(test_pkg_dir, "src", "$(test_pkg_name).jl"), "w") do io
        println(io, "module $(test_pkg_name)")
        println(io, "end")
    end
    
    # Initialize git repo
    repo = LibGit2.init(test_pkg_dir)
    
    # Add files and commit
    LibGit2.add!(repo, ".")
    LibGit2.commit(repo, "Initial commit"; author=LibGit2.Signature("Test", "test@example.com"), committer=LibGit2.Signature("Test", "test@example.com"))
    
    # Add remote (using HTTPS for testing)
    if Sys.iswindows()
        run(Cmd(`cmd /c git remote add origin https://github.com/tensor4all/TestPkgManual.jl.git`, dir=test_pkg_dir))
    else
        run(Cmd(`git remote add origin https://github.com/tensor4all/TestPkgManual.jl.git`, dir=test_pkg_dir))
    end
    
    # LibGit2.init() creates a repo on the default branch (usually main), so no need to create it
    
    @testset "read_project_meta" begin
        name, uuid, version, deps, compat = T4ARegistrator.read_project_meta(test_pkg_dir)
        @test name == test_pkg_name
        @test string(uuid) == test_uuid
        @test version == VersionNumber(test_version)
        @test deps isa Dict
        @test compat isa Dict
    end
    
    @testset "fix_compat_toml_format" begin
        # Test case 1: String array representation should be converted to actual array
        compat_data1 = Dict(
            "[0]" => Dict(
                "BitIntegers" => "0.3.5 - 0.3",
                "QuanticsGrids" => "[0.3, 0.6]",
                "T4ATensorCI" => "0.10",
                "julia" => "1.6.0 - 1"
            )
        )
        fixed1 = T4ARegistrator.fix_compat_toml_format(compat_data1)
        @test fixed1["[0]"]["BitIntegers"] == "0.3.5 - 0.3"  # Regular string, unchanged
        @test fixed1["[0]"]["QuanticsGrids"] == ["0.3", "0.6"]  # Converted to array
        @test fixed1["[0]"]["T4ATensorCI"] == "0.10"  # Regular string, unchanged
        @test fixed1["[0]"]["julia"] == "1.6.0 - 1"  # Regular string, unchanged
        
        # Test case 2: Already correct format (array) should remain unchanged
        compat_data2 = Dict(
            "[0]" => Dict(
                "EllipsisNotation" => "1",
                "QuanticsTCI" => "0.7",
                "SparseIR" => ["0.96 - 0.97", "1"],
                "StaticArrays" => "1",
                "T4APartitionedMPSs" => "0.7.3 - 0.7",
                "julia" => "1"
            )
        )
        fixed2 = T4ARegistrator.fix_compat_toml_format(compat_data2)
        @test fixed2["[0]"]["EllipsisNotation"] == "1"
        @test fixed2["[0]"]["QuanticsTCI"] == "0.7"
        @test fixed2["[0]"]["SparseIR"] == ["0.96 - 0.97", "1"]  # Already array, unchanged
        @test fixed2["[0]"]["StaticArrays"] == "1"
        @test fixed2["[0]"]["T4APartitionedMPSs"] == "0.7.3 - 0.7"
        @test fixed2["[0]"]["julia"] == "1"
        
        # Test case 3: Empty array string
        compat_data3 = Dict(
            "[0]" => Dict(
                "SomePackage" => "[]"
            )
        )
        fixed3 = T4ARegistrator.fix_compat_toml_format(compat_data3)
        @test fixed3["[0]"]["SomePackage"] == String[]
        
        # Test case 4: Multiple version sections
        compat_data4 = Dict(
            "[0]" => Dict("julia" => "1"),
            "[\"0.1.0\"]" => Dict("SomePackage" => "[0.1, 0.2]")
        )
        fixed4 = T4ARegistrator.fix_compat_toml_format(compat_data4)
        @test fixed4["[0]"]["julia"] == "1"
        @test fixed4["[\"0.1.0\"]"]["SomePackage"] == ["0.1", "0.2"]
    end
    
    # Note: Full register_manual() test would require:
    # - A mock registry or test registry
    # - Network access or mocking git operations
    # - This is better suited as an integration test
    # For now, we test the helper functions that can be tested in isolation
end

