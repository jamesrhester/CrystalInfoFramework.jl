using Documenter, CrystalInfoFramework

makedocs(sitename="CrystalInfoFramework documentation",
	  format = Documenter.HTML(
				   prettyurls = get(ENV,"CI",nothing) == "true"
				   ),
          #doctest = :fix
	  )

deploydocs(
    repo = "github.com/jamesrhester/CrystalInfoFramework.jl.git",
)
