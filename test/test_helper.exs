ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(Demo.Repo, :manual)

{:ok, _} = Application.ensure_all_started(:wallaby)
Application.put_env(:wallaby, :base_url, DemoWeb.Endpoint.url)
