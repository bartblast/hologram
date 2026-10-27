defmodule HologramFeatureTests.ResponseHeaders.Page1 do
  use Hologram.Page

  route "/response-headers/1"

  layout HologramFeatureTests.Components.DefaultLayout

  middleware :no_store

  def no_store(server, _opts) do
    put_response_header(server, "cache-control", "no-store")
  end

  def template do
    ~HOLO"""
    <h1>Response Headers / Page 1</h1>
    """
  end
end
