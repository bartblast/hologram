# DEFER: refactor & test
defmodule Hologram.Runtime.Controller do
  use Phoenix.Controller
  alias Hologram.Template.Renderer

  def index(conn, params) do
    module = conn.private.hologram_page
    output = Renderer.render(module, params)
    html(conn, output)
  end
end
