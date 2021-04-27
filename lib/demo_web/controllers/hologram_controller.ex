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

    js =
      Transpiler.Helpers.module_name_parts(module)
      |> Transpiler.Builder.build()

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
    window.pageModule = #{class_name};
    window.pageModuleName = '#{class_name}'
    window.state = {}//#{class_name}.state();
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
