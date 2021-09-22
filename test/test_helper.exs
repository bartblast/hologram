ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Hologram.Repo, :manual)

{:ok, _} = Application.ensure_all_started(:wallaby)
Application.put_env(:wallaby, :base_url, Hologram.E2E.Web.Endpoint.url)
