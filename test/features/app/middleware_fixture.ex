defmodule HologramFeatureTests.MiddlewareFixture do
  use Hologram.Middleware

  @impl Hologram.Middleware
  def call(server, _opts) do
    put_stash(server, :shared, "shared step ran")
  end
end
