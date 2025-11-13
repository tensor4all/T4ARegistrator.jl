module T4ARegistrator

using LibGit2
using TOML: TOML
using Pkg

using LocalRegistry: LocalRegistry, find_package_path
using LocalRegistry.RegistryTools: RegistryTools

export bumppatch, bumpminor, bumpmajor
include("PkgBump/PkgBump.jl")
using .PkgBump

export register, register_manual

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
    compute_subpath(name::String) -> String

Compute the subpath for a package in the registry (e.g., "T/TestPackage").
"""
function compute_subpath(name::String)
    initial = uppercase(first(name))
    return "$initial/$name"
end

"""
    read_project_meta(package_dir::String) -> (name::String, uuid::UUID, version::VersionNumber, deps::Dict, compat::Dict)

Read package metadata from Project.toml.
"""
function read_project_meta(package_dir::String)
    local pkg = nothing
    local d = Dict()
    for project_file in Base.project_names
        p = joinpath(package_dir, project_file)
        if isfile(p)
            pkg = RegistryTools.Project(p)
            d = TOML.parsefile(p)
            break
        end
    end
    
    if pkg === nothing || isnothing(pkg.name)
        error("Package does not have a Project.toml or JuliaProject.toml file")
    end
    if isnothing(pkg.uuid)
        error("Package does not have a UUID")
    end
    if isnothing(pkg.version)
        error("Package does not have a version")
    end
    
    deps = get(d, "deps", Dict{String,Any}())
    compat = get(d, "compat", Dict{String,Any}())
    
    return pkg.name, pkg.uuid, pkg.version, deps, compat
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
    registry_url = "https://github.com/tensor4all/T4ARegistry.git"
    
    # Create a temporary working directory for the registry clone
    # This avoids modifying Julia's managed registry and makes it easier to access the registration branch
    registry_workdir = mktempdir()
    atexit(() -> rm(registry_workdir; recursive=true, force=true))
    
    # Clone the registry into the temporary directory
    gitconfig = Dict()
    try
        if Sys.iswindows()
            run(Cmd(`cmd /c git clone -q $(registry_url) .`, dir=registry_workdir))
        else
            run(Cmd(`git clone -q $(registry_url) .`, dir=registry_workdir))
        end
    catch e
        rm(registry_workdir; recursive=true, force=true)
        error("Failed to clone registry from $(registry_url): $e")
    end
    
    # Determine if the package existed in the registry BEFORE registration
    registry_repo = LibGit2.GitRepo(registry_workdir)
    registry_toml = joinpath(registry_workdir, "Registry.toml")
    package_existed_before = false
    if isfile(registry_toml)
        registry_data = TOML.parsefile(registry_toml)
        pkg_uuid_str = string(pkg.uuid)
        package_existed_before = haskey(registry_data, "packages") && haskey(registry_data["packages"], pkg_uuid_str)
    end

    # Register the package using the temporary registry clone
    LocalRegistry.register(
        package_dir;
        registry = registry_workdir,
        branch = branch,
        commit = true,
        push = true,
    )

    # After registration, checkout the registration branch to update Package.toml
    # LocalRegistry.register() creates the branch, pushes it, then switches back to main and deletes the local branch
    # So we need to fetch and checkout the remote branch
    LibGit2.fetch(registry_repo)
    try
        # Create a local branch tracking the remote branch
        # LibGit2.branch!() returns the branch reference
        branch_ref = LibGit2.branch!(registry_repo, branch; track="origin/$(branch)")
        if branch_ref !== nothing
            LibGit2.checkout!(registry_repo, branch_ref)
        else
            @warn "Could not create branch $(branch). Package.toml may not be updated."
        end
    catch e
        @warn "Could not checkout branch $(branch). Package.toml may not be updated. Error: $e"
    end
    
    registry_path = registry_workdir
    # Always normalize the repo URL to HTTPS in the registry.
    # This covers both new registrations and updates of existing packages.
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
                old_repo = get(package_data, "repo", "")
                package_data["repo"] = package_repo
                # Only commit if the URL actually changed
                if old_repo != package_repo
                    open(package_toml, "w") do io
                        TOML.print(io, package_data)
                    end

                    # Commit the change on the same registration branch
                    registry_repo = LibGit2.GitRepo(registry_path)
                    LibGit2.add!(registry_repo, relpath(package_toml, registry_path))
                    LibGit2.commit(registry_repo, "Update repo URL to HTTPS format")
                    LibGit2.push(registry_repo, refspecs=["refs/heads/$(branch)"])
                else
                    @info "Package.toml repo URL is already HTTPS: $package_repo"
                end
            else
                @warn "Package.toml not found at: $package_toml"
            end
        else
            @warn "Package UUID $pkg_uuid_str not found in Registry.toml packages"
        end
    else
        @warn "Registry.toml not found at: $registry_toml"
    end

    @info "Hint: you can create a new pull request to GitHub repository via GitHub CLI:"

    pr_title = "$(LocalRegistry.commit_title(pkg, !package_existed_before))"

    tree_hash, _, _ = LocalRegistry.get_tree_hash(package_dir, gitconfig)

    pr_body = "UUID: $(pkg.uuid)\nRepo: $(package_repo)\nTree: $(string(tree_hash))"
    command = "gh pr create --repo tensor4all/T4ARegistry --base $(defaultbranch) --head $(branch) --title \"$(pr_title)\" --body \"$(pr_body)\""
    println(command)
    @info "Hint: you can merge the pull request via GitHub CLI:"
    println("gh pr merge --repo tensor4all/T4ARegistry $(branch) --merge --auto --delete-branch")
    return true
end

"""
    register_manual(package::Union{Module,Nothing} = nothing)

Manually register a package to T4ARegistry without using LocalRegistry.register().
This function clones the registry, writes all necessary files, and creates a PR.
"""
function register_manual(package::Union{Module,Nothing} = nothing)
    package_dir = find_package_path(package)
    
    # Check that we're on main/master branch
    repo = LibGit2.GitRepo(package_dir)
    current_branch = LibGit2.branch(repo)
    current_branch in ["main", "master"] || error("""You are working on "$(current_branch)".
                                                  Please checkout on the default branch i.e., "main" or "master".
                                                  """)
    defaultbranch = deepcopy(current_branch)
    
    # Read package metadata
    name, uuid, version, deps, compat = read_project_meta(package_dir)
    v = VersionNumber(version)
    branch = "register-$(name)-$(v)"
    registry_url = "https://github.com/tensor4all/T4ARegistry.git"
    
    # Get package repo URL and convert to HTTPS
    gitconfig = Dict()
    package_repo = LocalRegistry.get_remote_repo(package_dir, gitconfig)
    package_repo = ssh_to_https_url(package_repo)
    
    # Compute tree hash
    tree_hash, subdir, commit_hash = LocalRegistry.get_tree_hash(package_dir, gitconfig)
    
    # Create temporary directory for registry clone
    registry_workdir = mktempdir()
    atexit(() -> rm(registry_workdir; recursive=true, force=true))
    
    # Clone registry
    try
        if Sys.iswindows()
            run(Cmd(`cmd /c git clone -q $(registry_url) .`, dir=registry_workdir))
        else
            run(Cmd(`git clone -q $(registry_url) .`, dir=registry_workdir))
        end
    catch e
        rm(registry_workdir; recursive=true, force=true)
        error("Failed to clone registry from $(registry_url): $e")
    end
    
    registry_repo = LibGit2.GitRepo(registry_workdir)
    
    # Check if package already exists
    registry_toml_path = joinpath(registry_workdir, "Registry.toml")
    registry_data = TOML.parsefile(registry_toml_path)
    pkg_uuid_str = string(uuid)
    package_existed_before = haskey(registry_data, "packages") && haskey(registry_data["packages"], pkg_uuid_str)
    
    # Compute subpath
    subpath = compute_subpath(name)
    package_path = joinpath(registry_workdir, subpath)
    mkpath(package_path)
    
    # Update Registry.toml
    if !haskey(registry_data, "packages")
        registry_data["packages"] = Dict{String,Any}()
    end
    registry_data["packages"][pkg_uuid_str] = Dict("name" => name, "path" => subpath)
    open(registry_toml_path, "w") do io
        TOML.print(io, registry_data)
    end
    
    # Write Package.toml
    package_toml_path = joinpath(package_path, "Package.toml")
    package_toml_data = Dict(
        "name" => name,
        "uuid" => pkg_uuid_str,
        "repo" => package_repo
    )
    open(package_toml_path, "w") do io
        TOML.print(io, package_toml_data)
    end
    
    # Write Versions.toml
    versions_toml_path = joinpath(package_path, "Versions.toml")
    existing_versions = Dict{String,String}()  # version -> tree_hash
    if package_existed_before && isfile(versions_toml_path)
        versions_data = TOML.parsefile(versions_toml_path)
        # Extract existing versions and their tree hashes
        for key in keys(versions_data)
            if startswith(key, "[\"") && endswith(key, "\"]")
                # Extract version from key like ["0.10.0"]
                version_str = key[3:end-2]  # Remove [" and "]
                tree_hash_str = get(versions_data[key], "git-tree-sha1", "")
                existing_versions[version_str] = tree_hash_str
            end
        end
    end
    # Add new version
    existing_versions[string(v)] = string(tree_hash)
    # Write Versions.toml in correct format: ["0.10.0"] followed by git-tree-sha1
    open(versions_toml_path, "w") do io
        for (ver, hash) in existing_versions
            println(io, "[\"$(ver)\"]")
            println(io, "git-tree-sha1 = \"$(hash)\"")
        end
    end
    
    # Write Deps.toml (minimal for now - just empty structure)
    deps_toml_path = joinpath(package_path, "Deps.toml")
    deps_toml_data = Dict("[0]" => Dict{String,Any}())
    # TODO: Parse deps from Project.toml and convert to UUIDs
    open(deps_toml_path, "w") do io
        TOML.print(io, deps_toml_data)
    end
    
    # Write Compat.toml (minimal for now - just empty structure)
    compat_toml_path = joinpath(package_path, "Compat.toml")
    compat_toml_data = Dict("[0]" => Dict{String,Any}())
    # TODO: Parse compat from Project.toml and convert to version ranges
    open(compat_toml_path, "w") do io
        TOML.print(io, compat_toml_data)
    end
    
    # Ensure we're on main branch first - use git CLI for reliability
    if Sys.iswindows()
        run(Cmd(`cmd /c git checkout -q main`, dir=registry_workdir))
    else
        run(Cmd(`git checkout -q main`, dir=registry_workdir))
    end
    
    # Create branch using git CLI
    if Sys.iswindows()
        run(Cmd(`cmd /c git checkout -q -b $(branch)`, dir=registry_workdir))
    else
        run(Cmd(`git checkout -q -b $(branch)`, dir=registry_workdir))
    end
    
    # Add all changes, commit, and push using git CLI
    commit_title = package_existed_before ? "New version: $(name) v$(v)" : "New package: $(name) v$(v)"
    commit_message = """$(commit_title)

UUID: $(uuid)
Repo: $(package_repo)
Tree: $(string(tree_hash))"""
    
    if Sys.iswindows()
        run(Cmd(`cmd /c git add .`, dir=registry_workdir))
        run(Cmd(`cmd /c git commit -qm $(commit_message)`, dir=registry_workdir))
        run(Cmd(`cmd /c git push -q --set-upstream origin $(branch)`, dir=registry_workdir))
    else
        run(Cmd(`git add .`, dir=registry_workdir))
        run(Cmd(`git commit -qm $(commit_message)`, dir=registry_workdir))
        run(Cmd(`git push -q --set-upstream origin $(branch)`, dir=registry_workdir))
    end
    
    # Create PR via gh CLI or show command
    pr_title = commit_title
    pr_body = "UUID: $(uuid)\nRepo: $(package_repo)\nTree: $(string(tree_hash))"
    command = "gh pr create --repo tensor4all/T4ARegistry --base $(defaultbranch) --head $(branch) --title \"$(pr_title)\" --body \"$(pr_body)\""
    
    @info "Registration complete! Created branch: $(branch)"
    @info "To create a pull request, run:"
    println(command)
    @info "Or merge the PR via:"
    println("gh pr merge --repo tensor4all/T4ARegistry $(branch) --merge --auto --delete-branch")
    
    return true
end

end
