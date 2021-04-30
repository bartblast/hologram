# DEFER: test
defmodule DemoWeb.HologramController do
  use DemoWeb, :controller

  alias Hologram.TemplateEngine
  alias Hologram.Transpiler

  def index(conn, params) do
    module = conn.private.hologram_view

    state = module.state()
    hydrated_state = Transpiler.Hydrator.hydrate(state)

    template_ast =
      module.render()
      |> TemplateEngine.Parser.parse!()
      |> TemplateEngine.Transformer.transform()

    # DEFER: use .holo template files
    html = TemplateEngine.Renderer.render(template_ast, state)

    template_ir = TemplateEngine.IRGenerator.generate(template_ast, state)

    js =
      Transpiler.Helpers.module_name_parts(module)
      |> Transpiler.Builder.build()

    class_name =
      module
      |> to_string()
      |> String.split(".")
      |> tl()
      |> Enum.join("")

    html(conn, generate_html(conn, html, template_ir, class_name, js, hydrated_state))
  end

  defp generate_html(conn, html, template_ir, class_name, js, hydrated_state) do
    """
    <!DOCTYPE html>
    <html>
      <head>
        <title>Hologram Demo</title>
        <script  src="#{Routes.static_path(conn, "/js/hologram.js")}"></script>
        <script>
    #{js}
    window.state = #{hydrated_state};
    window.template = #{template_ir};
    Hologram.startEventLoop(window, #{class_name}, '#{class_name}')
        </script>
      </head>
      <body>
    #{html}
      </body>
    </html>
    """
  end
end
