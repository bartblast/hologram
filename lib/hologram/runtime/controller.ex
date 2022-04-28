# DEFER: refactor & test
defmodule Hologram.Runtime.Controller do
  use Phoenix.Controller

  alias Hologram.Conn
  alias Hologram.Template.Renderer

  def index(phx_conn, params) do
    module = phx_conn.private.hologram_page
    holo_conn = %Conn{params: params}
    bindings = %{}

    output = Renderer.render(module, holo_conn, bindings)
    html(phx_conn, output)
  end
end
