defmodule HologramFeatureTests.Middleware.Composite do
  use Hologram.Middleware

  middleware HologramFeatureTests.Middleware.Shared
  middleware :nested

  def nested(server, _opts) do
    put_stash(server, :nested, "nested middleware")
  end
end
