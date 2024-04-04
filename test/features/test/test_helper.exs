ExUnit.start()

{:ok, _apps} = Application.ensure_all_started(:wallaby)
Application.put_env(:wallaby, :base_url, HologramFeatureTestsWeb.Endpoint.url())
