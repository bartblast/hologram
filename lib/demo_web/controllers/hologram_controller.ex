# DEFER: refactor & test
defmodule DemoWeb.HologramController do
  use DemoWeb, :controller

  alias Hologram.Compiler
  alias Hologram.Compiler.{Helpers, Hydrator, Processor}
  alias Hologram.Template

  def index(conn, params) do
    module = conn.private.hologram_page

    state = module.state()
    hydrated_state = Hydrator.hydrate(state)
    virtual_dom = Template.Builder.build(module)
    IO.inspect(virtual_dom)

    # DEFER: use .holo template files
    html = Template.Renderer.render(virtual_dom, state)

    js =
      Helpers.module_name_segments(module)
      |> Compiler.Builder.build()

    class_name =
      module
      |> to_string()
      |> String.split(".")
      |> tl()
      |> Enum.join("")

    html(conn, generate_html(conn, html, class_name, js, hydrated_state))
  end

  defp generate_html(conn, html, class_name, js, hydrated_state) do
    """
    <!DOCTYPE html>
    <html>
      <head>
        <title>Hologram Demo</title>
        <script src="#{Routes.static_path(conn, "/js/hologram.js")}"></script>
        <script>
    #{js}
    window.state = #{hydrated_state};
    Hologram.start_runtime(window, #{class_name}, '#{class_name}')
        </script>
      </head>
    #{html}
    </html>
    """
  end
end
