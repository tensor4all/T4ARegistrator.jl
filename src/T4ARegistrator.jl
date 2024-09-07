module T4ARegistrator

using LibGit2
using TOML: TOML

using LocalRegistry: LocalRegistry, find_package_path

export bumppatch, bumpminor, bumpmajor
include("PkgBump/PkgBump.jl")
using .PkgBump

export register

"""
    register(targetpkg::Module)
    register()

Register `package::Module`. If `package` is omitted, register the package in
the currently active project or in the current directory in case the
active project is not a package.
"""
function register(package::Union{Module,Nothing} = nothing)
    package_dir = find_package_path(package)

    repo = LibGit2.GitRepo(package_dir)
    current_branch = LibGit2.branch(repo)
    current_branch in ["main", "master"] || error("""You are working on "$(current_branch)".
                                                  Please checkout on the default branch i.e., "main" or "master".
                                                  """)

    d = Dict()
    for project_file in Base.project_names
        p = joinpath(package_dir, project_file)
        if isfile(p)
            d = TOML.parsefile(p)
        end
    end

    name = get(d, "name", nothing)
    version = get(d, "version", nothing)
    if isnothing(name)
        error("$(package) does not have a Project.toml or JuliaProject.toml file")
    end
    if isnothing(version)
        error("$(package) is not a valid package (no version)")
    end
    v = VersionNumber(version)
    branch = "register-$(name)-$(v)"
    return LocalRegistry.register(
        package_dir;
        registry = "git@github.com:tensor4all/T4ARegistry.git",
        branch = branch,
        commit = true,
        push = true,
    )
end

end
