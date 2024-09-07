module PkgBump

using Pkg: Pkg
using LibGit2

export bumpmajor, bumpminor, bumppatch

include("versionupdate.jl")

"""
    bump(mode::Symbol; commit=true, push=true)

Bumps the version of the current active project according to `mode`, commits the change to a new branch, and pushes the branch to the remote repository.
"""
function bump(mode::Symbol; commit::Bool = true, push::Bool = true)::Nothing
    mode ∈ [:patch, :minor, :major] ||
        error("Expected one of [:patch, :minor, :major], actual $(mode)")

    # ensure project_file should be a type of String
    project_file = Base.active_project()::String
    project_dir = dirname(project_file)
    repo = LibGit2.GitRepo(project_dir)
    current_branch = LibGit2.branch(repo)
    current_branch in ["main", "master"] ||
        error("""You are working on "$(current_branch)".
              Please checkout on the default branch i.e., "main" or "master".
              """)

    if commit
        !LibGit2.isdirty(repo) ||
            error("Registry directory is dirty. Stash or commit files.")
    end

    project = Pkg.Types.read_project(project_file)
    current_version = project.version

    updateversion!(project, project_file, mode)
    new_version = project.version
    @info "Update version from $(current_version) to $(new_version)"

    try
        if commit
            branch = "pkgbump/bump-to-version-$(new_version)"
            @info "Switch branch from $(current_branch) to $branch"
            LibGit2.branch!(repo, branch)

            target_file = relpath(project_file, LibGit2.path(repo))
            @info "Stage $(target_file)"
            LibGit2.add!(repo, target_file)

            @info "Commit changes..."
            LibGit2.commit(repo, "Bump to version $(new_version)")
        else
            @info "Skipped git commit ... since commit keyword is set to $(commit)"
        end

        if push
            @info "Push to origin..."
            run(`git -C $(project_dir) push --set-upstream origin $branch`)
            @info "Hint: you can create a new pull request to GitHub repository via GitHub CLI:"
            basebranch = readchomp(`git -C . rev-parse --abbrev-ref HEAD`) # e.g., main or master
            @info "gh pr create --base $(basebranch) --head $(branch) --title \"Bump version to $(new_version)\" --body \"This PR updates version to $(new_version)\""
            @info "Hint: you can merge the pull request via GitHub CLI:"
            @info "gh pr merge $(branch) --merge --auto --delete-branch"
        else
            @info "Skipped git push ... since push keyword is set to $(push)"
        end
    catch e
        println("Failed to commit or push with error $e")
    finally
        @info "Switch back to $(current_branch)"
        LibGit2.branch!(repo, current_branch)
    end

    @info "Done"
end

"""
    bumppatch(;kwargs)

Bump the patch version of the current active project, commit, and push the changes.
"""
bumppatch(; kwargs...) = bump(:patch; kwargs...)

"""
    bumpminor(;kwargs)

Bump the minor version of the current active project, commit, and push the changes.
"""
bumpminor(; kwargs...) = bump(:minor; kwargs...)

"""
    bumpmajor(;kwargs)

Bump the major version of the current active project, commit, and push the changes.
"""
bumpmajor(; kwargs...) = bump(:major; kwargs...)

end # module
