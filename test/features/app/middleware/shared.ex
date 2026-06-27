defmodule HologramFeatureTests.Middleware.Shared do
  use Hologram.Middleware

  @impl Hologram.Middleware
  def call(server, _opts) do
    put_stash(server, :shared, "shared middleware ran")
  end
end
