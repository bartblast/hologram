defmodule Hologram.Test.Fixtures.Middleware.Module1 do
  use Hologram.Middleware

  @impl Hologram.Middleware
  def call(server, opts) do
    append_response_header(server, "vary", opts[:value])
  end
end
