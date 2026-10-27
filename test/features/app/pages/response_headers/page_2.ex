defmodule HologramFeatureTests.ResponseHeaders.Page2 do
  use Hologram.Page

  route "/response-headers/2"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, server) do
    {component, put_response_header(server, "x-robots-tag", "noindex")}
  end

  def template do
    ~HOLO"""
    <h1>Response Headers / Page 2</h1>
    """
  end
end
