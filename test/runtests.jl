using T4ARegistrator
using Test
using Aqua
using JET

@testset "T4ARegistrator.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(T4ARegistrator; ambiguities=false, deps_compat=false)
    end
    
    v = VERSION
    isreleased = v.prerelease == ()
    if isreleased && v >= v"1.9"
        @testset "Code linting (JET.jl)" begin
            JET.test_package(T4ARegistrator; target_defined_modules=true)
        end
    end
end
