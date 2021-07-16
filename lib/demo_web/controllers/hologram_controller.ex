# DEFER: refactor & test
defmodule DemoWeb.HologramController do
  use DemoWeb, :controller

  alias Hologram.Compiler.Hydrator
  alias Hologram.Template.{Builder, Renderer}

  def index(conn, _params) do
    module = conn.private.hologram_page

    state = module.state()
    hydrated_state = Hydrator.hydrate(state)
    virtual_dom = Builder.build(module)

    # DEFER: use .holo template files
    html = Renderer.render(virtual_dom, state)

    class_name =
      module
      |> to_string()
      |> String.split(".")
      |> tl()
      |> Enum.join("")

    html(conn, generate_html(module, conn, html, class_name, hydrated_state))
  end

  defp generate_html(module, conn, html, class_name, hydrated_state) do
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
          Hologram.run(window, #{class_name}, #{hydrated_state})
        </script>
      </head>
    #{html}
    </html>
    """
  end
end
