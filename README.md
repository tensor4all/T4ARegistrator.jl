[![CI](https://github.com/tensor4all/T4ARegistrator.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/tensor4all/T4ARegistrator.jl/actions/workflows/CI.yml)

# T4ARegistrator.jl

This package simplifies managing Julia packages within the tensor4all group. It provides functionalities for:

- Creating pull requests to register Julia packages in [tensor4all/T4ARegistry](https://github.com/tensor4all/T4ARegistry).
- Updating the version number of a user-specified package.

**Please note:** This package is intended for internal use by the tensor4all group.

# Setup

```julia
julia> using Pkg
using Pkg; Pkg.Registry.add(RegistrySpec(url="https://github.com/tensor4all/T4ARegistry.git"))
julia> using Pkg; Pkg.add("T4ARegistrator")
```

# Bumping Version in Project.toml

Scenario: You've updated code in TensorCrossinterpolation.jl and want to create a pull request to bump the patch version.

Here's how to do it:

```sh
$ cd <path/to/TensorCrossinterpolation.jl>
$ julia --project=@.
$ julia> using T4ARegistrator
$ julia> bumppatch()  # Updates version from 'x.y.z' to 'x.y.(z+1)'.
```

It will modify `Project.toml` to update the version of TensorCrossinterpolation.jl. By default, it will push changes to remote repository tensor4all/TensorCrossinterpolation.jl with a branch named "pkgbump/bump-to-version-<new_version>". You can disable this behaviour by setting `bumppatch(push=false)`.

Additional options:

`bumpminor()`: Increases the minor version number.
`bumpmajor()`: Increases the major version number.

# Registering Packages in [tensor4all/T4ARegistry](https://github.com/tensor4all/T4ARegistry)

Scenario: You've updated code in TensorCrossinterpolation.jl and want to register the new version in tensor4all/T4ARegistry.

Here's how to do it:

```sh
$ cd <path/to/TensorCrossinterpolation.jl>
$ julia --project=@. `using T4ARegistrator; register()`
```

This will register to [tensor4all/T4ARegistry](https://github.com/tensor4all/T4ARegistry) with branch named "register-<package name>-<new version>".

# GitHub CLI

[GitHub CLI](https://cli.github.com/) a.k.a `gh` command provides a convenient way to create/meger PR automatically.

## Using GitHub CLI Command to create a new pull request automatically

Here is an example of how to use GitHub CLI to create a new pull request.

```sh
$ git switch -c update-readme
$ git add README.md
$ git commit -m "Update README.md"
$ git push origin update-readme
$ gh pr create --base main --title "Improve README.md" --body "This PR updates README.md"

Creating pull request for terasaki/improve-readme into main in tensor4all/T4ARegistrator.jl

https://github.com/tensor4all/T4ARegistrator.jl/pull/9
```

## Using GitHub CLI Command to merge submitted PR automatically

Continuation of the above section, you can merge the PR into the main branch automatically.

```sh
$ gh pr merge --merge --auto --delete-branch
✓ Pull request tensor4all/T4ARegistrator.jl#9 will be automatically merged when all requirements are met
```
