defmodule Hologram.Test.Fixtures.Middleware.Builder.Module1 do
  use Hologram.Middleware

  @impl Hologram.Middleware
  def call(server, opts), do: put_stash(server, :ran, opts)
end
