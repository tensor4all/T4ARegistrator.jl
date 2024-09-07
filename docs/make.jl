using T4ARegistrator
using T4ARegistrator.PkgBump
using Documenter

DocMeta.setdocmeta!(
    T4ARegistrator,
    :DocTestSetup,
    :(using T4ARegistrator);
    recursive = true,
)
DocMeta.setdocmeta!(PkgBump, :DocTestSetup, :(using PkgBump); recursive = true)

makedocs(;
    modules = [T4ARegistrator],
    authors = "tensor4all group and contributors",
    sitename = "T4ARegistrator.jl",
    format = Documenter.HTML(;
        canonical = "https://tensor4all.github.io/T4ARegistrator.jl",
        edit_link = "main",
        assets = String[],
    ),
    pages = ["Home" => "index.md"],
)

deploydocs(; repo = "github.com/tensor4all/T4ARegistrator.jl", devbranch = "main")
