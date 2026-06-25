defmodule Hologram.Test.Fixtures.Middleware.Module2 do
  use Hologram.Middleware

  @impl Hologram.Middleware
  def call(server, _opts) do
    put_status(server, :forbidden)
  end
end
