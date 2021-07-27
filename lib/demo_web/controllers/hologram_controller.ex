# DEFER: refactor & test
defmodule DemoWeb.HologramController do
  use DemoWeb, :controller

  alias Hologram.Compiler.{Helpers, Serializer}
  alias Hologram.Template.{Builder, Renderer}

  def index(conn, _params) do
    module = conn.private.hologram_page

    state = module.state()
    serialized_state = Serializer.serialize(state)
    virtual_dom = Builder.build(module)

    # DEFER: use .holo template files
    html = Renderer.render(virtual_dom, state)

    html(conn, generate_html(module, conn, html, serialized_state))
  end

  defp generate_html(module, conn, html, serialized_state) do
    class_name = Helpers.class_name(module)

    # DEFER: optimize, e.g. load the manifest in config
    digest =
      File.cwd!() <> "/priv/static/hologram/manifest.json"
      |> File.read!()
      |> Jason.decode!()
      |> Map.get("#{module}")

    """
    <!DOCTYPE html>
    <html>
      <head>
        <title>Hologram Demo</title>
        <script src="#{Routes.static_path(conn, "/js/hologram.js")}"></script>
        <script src="#{Routes.static_path(conn, "/hologram/page-#{digest}.js")}"></script>
        <script>
          Hologram.run(window, #{class_name}, #{serialized_state})
        </script>
      </head>
    #{html}
    </html>
    """
  end
end
