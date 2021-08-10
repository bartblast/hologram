# DEFER: refactor & test
defmodule DemoWeb.HologramController do
  use DemoWeb, :controller
  alias Hologram.Template.Renderer

  def index(conn, params) do
    module = conn.private.hologram_page
    output = Renderer.render(module, params)
    html(conn, output)
  end
end
