defmodule Hologram.Test.Fixtures.Middleware.Builder.Module2 do
  use Hologram.Middleware.Builder

  alias Hologram.Server
  alias Hologram.Test.Fixtures.Middleware.Builder.Module1

  middleware Module1
  middleware Module1, role: :admin
  middleware :enrich

  @spec enrich(Server.t(), keyword()) :: Server.t()
  def enrich(server, _opts), do: server
end
