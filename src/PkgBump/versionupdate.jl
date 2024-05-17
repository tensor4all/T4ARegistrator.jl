
"""
    updateversion!(project::Pkg.Types.Project, project_file::AbstractString, mode::Symbol)

Update the version of the given project file according to the specified `mode` (:patch, :minor, :major).
The new version is written directly to the `project_file`.
"""
function updateversion!(
    project::Pkg.Types.Project,
    project_file::AbstractString,
    mode::Symbol
)
    isnothing(project.version) && (project.version = v"0.1.0")
    mode === :patch && (project.version = Base.nextpatch(project.version::VersionNumber))
    mode === :minor && (project.version = Base.nextminor(project.version::VersionNumber))
    mode === :major && (project.version = Base.nextmajor(project.version::VersionNumber))
    return Pkg.Types.write_project(project, project_file)
end

"""
    updatepatch!(project::Pkg.Types.Project, project_file::AbstractString)

Increment the patch version of the given project and write the changes to the `project_file`.
"""
function updatepatch!(project::Pkg.Types.Project, project_file::AbstractString)
    return updateversion!(project, project_file, :patch)
end

"""
    updateminor!(project::Pkg.Types.Project, project_file::AbstractString)

Increment the minor version of the given project and write the changes to the `project_file`.
"""
function updateminor!(project::Pkg.Types.Project, project_file::AbstractString)
    return updateversion!(project, project_file, :minor)
end

"""
    updatemajor!(project::Pkg.Types.Project, project_file)

Increment the major version of the given project and write the changes to the `project_file`.
"""
function updatemajor!(project::Pkg.Types.Project, project_file::AbstractString)
    return updateversion!(project, project_file, :major)
end

"""
    updateversion(project_file::AbstractString, mode::Symbol) -> Pkg.Types.Project

Read the project from `project_file`, update its version according to `mode`, and write the changes back.
Returns the updated project.
"""
function updateversion(project_file::AbstractString, mode::Symbol)
    project = Pkg.Types.read_project(project_file)
    updateversion!(project, project_file, mode)
    return project
end

"""
    updatepatch(project_file::AbstractString)

Update the patch version of the project defined in `project_file`.
"""
updatepatch(project_file::AbstractString) = updateversion(project_file, :patch)

"""
    updateminor(project_file::AbstractString)

Update the minor version of the project defined in `project_file`.
"""
updateminor(project_file::AbstractString) = updateversion(project_file, :minor)

"""
    updatemajor(project_file::AbstractString)

Update the major version of the project defined in `project_file`.
"""
updatemajor(project_file::AbstractString) = updateversion(project_file, :major)
