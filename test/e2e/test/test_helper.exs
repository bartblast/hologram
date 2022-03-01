alias Hologram.Compiler.Reflection
alias HologramE2E.Web.Endpoint

ExUnit.start()

Reflection.release_static_path() <> "/hologram/runtime*"
|> Path.wildcard()
|> Enum.each(&File.rm!/1)

Mix.Task.run("holo.assets.build")

{:ok, _} = Application.ensure_all_started(:wallaby)
Application.put_env(:wallaby, :base_url, Endpoint.url())
