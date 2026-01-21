using Documenter, CrystalInfoFramework

makedocs(sitename="CrystalInfoFramework documentation",
         pages = [
             "Overview" => "index.md",
             "Guide" => "tutorial.md",
             "API" => "api.md"
             ],
         #doctest = :fix
         warnonly = (:cross_references)
	  )

deploydocs(
    repo = "github.com/jamesrhester/CrystalInfoFramework.jl.git",
)
