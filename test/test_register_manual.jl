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
    
    # Note: Full register_manual() test would require:
    # - A mock registry or test registry
    # - Network access or mocking git operations
    # - This is better suited as an integration test
    # For now, we test the helper functions that can be tested in isolation
end

