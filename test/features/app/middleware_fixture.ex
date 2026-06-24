defmodule HologramFeatureTests.MiddlewareFixture do
  alias Hologram.Server

  @spec enrich(Server.t()) :: Server.t()
  def enrich(server) do
    Server.put_stash(server, :shared, "shared step ran")
  end
end
