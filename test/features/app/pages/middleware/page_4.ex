defmodule HologramFeatureTests.Middleware.Page4 do
  use Hologram.Page

  route "/middleware/4"

  layout HologramFeatureTests.Components.DefaultLayout

  middleware :deny

  def deny(server, _opts) do
    server
    |> put_response_header("content-type", "text/html; charset=utf-8")
    |> put_response_body("access forbidden by middleware")
    |> put_status(:forbidden)
  end

  def template do
    ~HOLO"""
    <h1>Middleware / Page 4</h1>
    """
  end
end
