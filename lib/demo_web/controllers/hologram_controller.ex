# DEFER: test
defmodule DemoWeb.HologramController do
  use DemoWeb, :controller

  alias Hologram.TemplateEngine
  alias Hologram.Transpiler

  def index(conn, params) do
    module = conn.private.hologram_view
    source = module.module_info()[:compile][:source]

    state = module.state()

    # DEFER: use .holo template files
    html =
      module.render()
      |> TemplateEngine.Parser.parse!()
      |> TemplateEngine.Transformer.transform()
      |> TemplateEngine.Renderer.render(state)

    # DEFER: implement Transpiler.transpile_file!/1
    js =
      Transpiler.Parser.parse_file!(source)
      |> Transpiler.Normalizer.normalize()
      |> Transpiler.Transformer.transform()
      |> Transpiler.Generator.generate()

    class_name =
      module
      |> to_string()
      |> String.split(".")
      |> tl()
      |> Enum.join("")

    html(conn, generate_html(conn, html, class_name, js))
  end

  defp generate_html(conn, html, class_name, js) do
    """
    <!DOCTYPE html>
    <html>
      <head>
        <title>Hologram Demo</title>
        <script  src="#{Routes.static_path(conn, "/js/hologram.js")}"></script>
        <script>
    #{js}
    window.modules = {
      "#{class_name}": #{class_name}
    }
    window.state = #{class_name}.state();
    Hologram.startEventLoop(window, '#{class_name}')
        </script>
      </head>
      <body>
    #{html}
      </body>
    </html>
    """
  end
end
