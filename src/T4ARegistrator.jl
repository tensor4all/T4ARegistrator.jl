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
    fix_compat_toml_format(compat_data::Dict) -> Dict

Fix Compat.toml format: convert string representations of arrays to actual arrays.
For example, "[0.3, 0.6]" (string) should become ["0.3", "0.6"] (array).
"""
function fix_compat_toml_format(compat_data::Dict)
    fixed_data = Dict{String,Any}()
    for (version_key, deps_dict) in compat_data
        if deps_dict isa Dict
            fixed_deps = Dict{String,Any}()
            for (dep_name, dep_value) in deps_dict
                if dep_value isa String
                    # Check if the string looks like an array representation: "[...]"
                    if startswith(dep_value, "[") && endswith(dep_value, "]")
                        # Parse the array string: "[0.3, 0.6]" -> ["0.3", "0.6"]
                        # Remove the outer brackets and split by comma
                        inner = strip(dep_value[2:end-1])
                        if isempty(inner)
                            # Empty array: "[]"
                            fixed_deps[dep_name] = String[]
                        else
                            # Split by comma and trim each element
                            elements = [strip(elem) for elem in split(inner, ",")]
                            fixed_deps[dep_name] = elements
                        end
                    else
                        # Regular string, keep as is
                        fixed_deps[dep_name] = dep_value
                    end
                elseif dep_value isa Vector
                    # Already an array, keep as is
                    fixed_deps[dep_name] = dep_value
                else
                    # Other types, keep as is
                    fixed_deps[dep_name] = dep_value
                end
            end
            fixed_data[version_key] = fixed_deps
        else
            # Not a dict, keep as is
            fixed_data[version_key] = deps_dict
        end
    end
    return fixed_data
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
    @info "Cloning registry to temporary directory: $(registry_workdir)"
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
    
    # Fetch all remote branches to get the latest state
    # This ensures we know about existing registration branches
    # Note: git clone only fetches the default branch, so we need to fetch all branches
    registry_repo = LibGit2.GitRepo(registry_workdir)
    try
        # Use git CLI to fetch all branches, as LibGit2.fetch() may not fetch all refs
        if Sys.iswindows()
            run(Cmd(`cmd /c git fetch --all`, dir=registry_workdir))
        else
            run(Cmd(`git fetch --all`, dir=registry_workdir))
        end
    catch e
        @warn "Failed to fetch all remote branches: $e"
        # Fallback to LibGit2.fetch()
        try
            LibGit2.fetch(registry_repo)
        catch e2
            @warn "Failed to fetch remote branches with LibGit2: $e2"
        end
    end
    
    # Check if the registration branch already exists remotely using git CLI
    # This is more reliable than LibGit2 for checking remote branches
    # If the branch exists, create a branch with a different name (e.g., add a suffix)
    original_branch = branch
    branch_suffix = 1
    while true
        branch_exists = false
        try
            if Sys.iswindows()
                cmd = Cmd(`cmd /c git ls-remote --heads origin $(branch)`, dir=registry_workdir)
            else
                cmd = Cmd(`git ls-remote --heads origin $(branch)`, dir=registry_workdir)
            end
            result = open(readchomp, pipeline(cmd))
            if !isempty(result)
                branch_exists = true
            end
        catch e
            # git ls-remote failed, assume branch doesn't exist
        end
        
        if !branch_exists
            # Found an available branch name
            if branch != original_branch
                @info "Branch '$(original_branch)' already exists, using '$(branch)' instead"
            end
            break
        end
        
        # Branch exists, try with a suffix
        branch = "$(original_branch)-$(branch_suffix)"
        branch_suffix += 1
        
        # Safety check: prevent infinite loop
        if branch_suffix > 100
            error("Too many branch name conflicts. Please clean up existing branches.")
        end
    end
    
    # Determine if the package existed in the registry BEFORE registration
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

    # After registration, checkout the registration branch to update Package.toml and Compat.toml
    # LocalRegistry.register() creates the branch, pushes it, then switches back to main and deletes the local branch
    # So we need to fetch and checkout the remote branch using git CLI for reliability
    try
        if Sys.iswindows()
            run(Cmd(`cmd /c git fetch origin $(branch)`, dir=registry_workdir))
            run(Cmd(`cmd /c git checkout -b $(branch) origin/$(branch)`, dir=registry_workdir))
        else
            run(Cmd(`git fetch origin $(branch)`, dir=registry_workdir))
            run(Cmd(`git checkout -b $(branch) origin/$(branch)`, dir=registry_workdir))
        end
        @info "Successfully checked out branch $(branch)"
    catch e
        @warn "Could not checkout branch $(branch). Package.toml and Compat.toml may not be updated. Error: $e"
    end
    
    registry_path = registry_workdir
    # Always normalize the repo URL to HTTPS in the registry.
    # This covers both new registrations and updates of existing packages.
    package_repo = LocalRegistry.get_remote_repo(package_dir, gitconfig)
    package_repo = ssh_to_https_url(package_repo)

    # Update Package.toml to use HTTPS URL and fix Compat.toml format
    # Get package path from Registry.toml
    # Note: After LocalRegistry.register(), we need to re-read Registry.toml from the checked-out branch
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

                    # Commit and push the change on the same registration branch using git CLI
                    if Sys.iswindows()
                        run(Cmd(`cmd /c git add $(relpath(package_toml, registry_path))`, dir=registry_path))
                        run(Cmd(`cmd /c git commit -m "Update repo URL to HTTPS format"`, dir=registry_path))
                        run(Cmd(`cmd /c git push origin $(branch)`, dir=registry_path))
                    else
                        run(Cmd(`git add $(relpath(package_toml, registry_path))`, dir=registry_path))
                        run(Cmd(`git commit -m "Update repo URL to HTTPS format"`, dir=registry_path))
                        run(Cmd(`git push origin $(branch)`, dir=registry_path))
                    end
                    @info "Updated Package.toml repo URL to HTTPS and pushed changes"
                else
                    @info "Package.toml repo URL is already HTTPS: $package_repo"
                end
            else
                @warn "Package.toml not found at: $package_toml"
            end
            
            # Fix Compat.toml format: convert string array representations to actual arrays
            compat_toml = joinpath(package_path, "Compat.toml")
            if isfile(compat_toml)
                compat_data = TOML.parsefile(compat_toml)
                fixed_compat_data = fix_compat_toml_format(compat_data)
                # Only update if there were changes
                if compat_data != fixed_compat_data
                    open(compat_toml, "w") do io
                        TOML.print(io, fixed_compat_data)
                    end
                    
                    # Commit and push the change on the same registration branch using git CLI
                    if Sys.iswindows()
                        run(Cmd(`cmd /c git add $(relpath(compat_toml, registry_path))`, dir=registry_path))
                        run(Cmd(`cmd /c git commit -m "Fix Compat.toml format: convert string arrays to actual arrays"`, dir=registry_path))
                        run(Cmd(`cmd /c git push origin $(branch)`, dir=registry_path))
                    else
                        run(Cmd(`git add $(relpath(compat_toml, registry_path))`, dir=registry_path))
                        run(Cmd(`git commit -m "Fix Compat.toml format: convert string arrays to actual arrays"`, dir=registry_path))
                        run(Cmd(`git push origin $(branch)`, dir=registry_path))
                    end
                    @info "Fixed Compat.toml format and pushed changes"
                else
                    @info "Compat.toml format is already correct, no changes needed"
                end
            else
                @warn "Compat.toml not found at: $compat_toml"
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
