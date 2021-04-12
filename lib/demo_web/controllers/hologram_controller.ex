# DEFER: test
defmodule DemoWeb.HologramController do
  use DemoWeb, :controller

  alias Hologram.TemplateEngine
  alias Hologram.Transpiler

  def index(conn, params) do
    module = conn.private.hologram_view
    source = module.module_info()[:compile][:source]

    # TODO: implement state
    state = %{}

    # DEFER: use .holo template files
    html =
      module.render(state)
      |> TemplateEngine.Parser.parse!()
      |> TemplateEngine.Transformer.transform()
      |> TemplateEngine.Renderer.render(state)

    # DEFER: implement Transpiler.transpile_file!/1
    js =
      Transpiler.Parser.parse_file!(source)
      |> Transpiler.Transformer.transform()
      |> Transpiler.Generator.generate()

    html(conn, generate_html(conn, html, js))
  end

  defp generate_html(conn, html, js) do
    """
    <!DOCTYPE html>
    <html>
      <head>
        <title>Hologram Demo</title>
        <script  src="#{Routes.static_path(conn, "/js/hologram.js")}"></script>
        <script>
    #{js}
        </script>
      </head>
      <body>
    #{html}
      </body>
    </html>
    """
  end
end
