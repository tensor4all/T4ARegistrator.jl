module T4ARegistrator

using LibGit2
using TOML: TOML

using LocalRegistry: LocalRegistry, find_package_path
using LocalRegistry.RegistryTools: RegistryTools

export bumppatch, bumpminor, bumpmajor
include("PkgBump/PkgBump.jl")
using .PkgBump

export register

"""
    ssh_to_https_url(ssh_url::String) -> String

Convert SSH URL (git@github.com:user/repo.git) to HTTPS URL (https://github.com/user/repo.git).
"""
function ssh_to_https_url(ssh_url::String)
    if startswith(ssh_url, "git@")
        # git@github.com:user/repo.git -> https://github.com/user/repo.git
        return replace(ssh_url, r"^git@([^:]+):" => s"https://\1/")
    end
    return ssh_url
end

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
    defaultbranch = deepcopy(current_branch)

    d = Dict()
    local pkg
    for project_file in Base.project_names
        p = joinpath(package_dir, project_file)
        pkg = RegistryTools.Project(p)
        if isfile(p)
            d = TOML.parsefile(p)
            break
        end
    end

    name = get(d, "name", nothing)
    version = get(d, "version", nothing)
    if isnothing(pkg.name)
        error("$(package) does not have a Project.toml or JuliaProject.toml file")
    end
    if isnothing(pkg.version)
        error("$(package) is not a valid package (no version)")
    end
    v = VersionNumber(version)
    branch = "register-$(name)-$(v)"
    registry = "https://github.com/tensor4all/T4ARegistry.git"

    LocalRegistry.register(
        package_dir;
        registry = registry,
        branch = branch,
        commit = true,
        push = true,
    )

    registry_path = LocalRegistry.find_registry_path(registry, pkg)
    gitconfig = Dict()
    registry_path, _ = LocalRegistry.check_git_registry(registry_path, gitconfig)
    new_package = !LocalRegistry.has_package(registry_path, pkg)
    if new_package
        package_repo = LocalRegistry.get_remote_repo(package_dir, gitconfig)
        package_repo = ssh_to_https_url(package_repo)
        
        # Update Package.toml to use HTTPS URL
        # Get package path from Registry.toml
        registry_toml = joinpath(registry_path, "Registry.toml")
        if isfile(registry_toml)
            registry_data = TOML.parsefile(registry_toml)
            pkg_uuid_str = string(pkg.uuid)
            if haskey(registry_data, "packages") && haskey(registry_data["packages"], pkg_uuid_str)
                package_path_rel = registry_data["packages"][pkg_uuid_str]["path"]
                package_path = joinpath(registry_path, package_path_rel)
                package_toml = joinpath(package_path, "Package.toml")
                if isfile(package_toml)
                    package_data = TOML.parsefile(package_toml)
                    package_data["repo"] = package_repo
                    open(package_toml, "w") do io
                        TOML.print(io, package_data)
                    end
                    
                    # Commit the change
                    registry_repo = LibGit2.GitRepo(registry_path)
                    LibGit2.add!(registry_repo, relpath(package_toml, registry_path))
                    LibGit2.commit(registry_repo, "Update repo URL to HTTPS format")
                    LibGit2.push(registry_repo, refspecs=["refs/heads/$(branch)"])
                end
            end
        end
    else
        package_repo = ""
    end

    @info "Hint: you can create a new pull request to GitHub repository via GitHub CLI:"

    pr_title = "$(LocalRegistry.commit_title(pkg, new_package))"

    tree_hash, _, _ = LocalRegistry.get_tree_hash(package_dir, gitconfig)

    pr_body = "UUID: $(pkg.uuid)\nRepo: $(package_repo)\nTree: $(string(tree_hash))"
    command = "gh pr create --repo tensor4all/T4ARegistry --base $(defaultbranch) --head $(branch) --title \"$(pr_title)\" --body \"$(pr_body)\""
    println(command)
    @info "Hint: you can merge the pull request via GitHub CLI:"
    println("gh pr merge --repo tensor4all/T4ARegistry $(branch) --merge --auto --delete-branch")
    return true
end

end
