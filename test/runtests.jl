using T4ARegistrator
using Test
using Aqua
using JET

@testset "T4ARegistrator.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(T4ARegistrator; ambiguities = false, deps_compat = false, stale_deps = false)
    end

    v = VERSION
    isreleased = v.prerelease == ()
    if isreleased && v >= v"1.9"
        @testset "Code linting (JET.jl)" begin
            JET.test_package(T4ARegistrator; target_modules = (T4ARegistrator,))
        end
    end

    @testset "Helper functions" begin
        @testset "ssh_to_https_url" begin
            @test T4ARegistrator.ssh_to_https_url("git@github.com:user/repo.git") == "https://github.com/user/repo.git"
            @test T4ARegistrator.ssh_to_https_url("https://github.com/user/repo.git") == "https://github.com/user/repo.git"
            @test T4ARegistrator.ssh_to_https_url("git@gitlab.com:user/repo.git") == "https://gitlab.com/user/repo.git"
        end

        @testset "compute_subpath" begin
            @test T4ARegistrator.compute_subpath("TestPackage") == "T/TestPackage"
            @test T4ARegistrator.compute_subpath("MyPackage") == "M/MyPackage"
            @test T4ARegistrator.compute_subpath("aPackage") == "A/aPackage"
        end
    end

    include("test_register_manual.jl")
end
