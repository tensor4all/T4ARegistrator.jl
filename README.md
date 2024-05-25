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

It will create a new pull request to TensorCrossinterpolation.jl that updates `Project.toml`

This will create a pull request to TensorCrossinterpolation.jl that updates the version number in `Project.toml`.

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

This will create a pull request to [tensor4all/T4ARegistry](https://github.com/tensor4all/T4ARegistry) to register the new version of TensorCrossinterpolation.jl.

