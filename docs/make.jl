using Documenter, CrystalInfoFramework

makedocs(sitename="CrystalInfoFramework documentation",
	  format = Documenter.HTML(
				   prettyurls = get(ENV,"CI",nothing) == "true"
				   ),
         pages = [
             "Overview" => "index.md",
             "Guide" => "tutorial.md",
             "API" => "api.md"
             ]
             #doctest = :fix
	  )

deploydocs(
    repo = "github.com/jamesrhester/CrystalInfoFramework.jl.git",
)
