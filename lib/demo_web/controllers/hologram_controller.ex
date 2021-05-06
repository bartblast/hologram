# DEFER: test
defmodule DemoWeb.HologramController do
  use DemoWeb, :controller

  alias Hologram.Template
  alias Hologram.Compiler.Builder
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.Hydrator
  alias Hologram.Compiler.Processor

  def index(conn, params) do
    module = conn.private.hologram_page

    state = module.state()
    hydrated_state = Hydrator.hydrate(state)

    template_ast =
      module.render()
      |> Template.Parser.parse!()
      |> Template.Transformer.transform()

    # DEFER: use .holo template files
    html = Template.Renderer.render(template_ast, state)

    template_ir = Template.IRGenerator.generate(template_ast, state)

    js =
      Helpers.module_name_parts(module)
      |> Builder.build()

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
    window.ir = { '#{class_name}': #{template_ir} };
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
