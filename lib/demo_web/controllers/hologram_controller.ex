# DEFER: refactor & test
defmodule DemoWeb.HologramController do
  use DemoWeb, :controller

  alias Hologram.Compiler.{Builder, Helpers, Hydrator, Processor}
  alias Hologram.Template
  alias Hologram.Template.VirtualDOM

  def index(conn, params) do
    module = conn.private.hologram_page

    state = module.state()
    hydrated_state = Hydrator.hydrate(state)
    virtual_dom = VirtualDOM.build(module)

    # DEFER: use .holo template files
    html = Template.Renderer.render(virtual_dom, state)

    template_ir = Template.Generator.generate(virtual_dom, state)

    js =
      Helpers.module_name_segments(module)
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
        <script src="#{Routes.static_path(conn, "/js/hologram.js")}"></script>
        <script>
    #{js}
    window.state = #{hydrated_state};
    window.ir = { '#{class_name}': #{template_ir} };
    Hologram.startEventLoop(window, #{class_name}, '#{class_name}')
        </script>
      </head>
    #{html}
    </html>
    """
  end
end
