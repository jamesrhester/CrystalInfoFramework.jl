using Documenter, CrystalInfoFramework

makedocs(sitename="CrystalInfoFramework documentation",
	  format = Documenter.HTML(
				   prettyurls = get(ENV,"CI",nothing) == "true"
				   )
	  )
