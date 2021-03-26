defmodule DemoWeb.HolografController do
  use DemoWeb, :controller

  alias Holograf.Transpiler.Generator
  alias Holograf.Transpiler.Parser
  alias Holograf.Transpiler.Transformer

  def index(conn, params) do
    module = conn.private.holograf_view
    source = module.module_info()[:compile][:source]

    # TODO: implement Transpiler.transpile_file!/1
    js =
      Parser.parse_file!(source)
      |> Transformer.transform()
      |> Generator.generate()

    html(conn, generate_html(conn, js))
  end

  defp generate_html(conn, js) do
    """
    <!DOCTYPE html>
    <html>
      <head>
        <title>Holograf Demo</title>
        <script  src="#{Routes.static_path(conn, "/js/holograf.js")}"></script>
        <script>
    #{js}
        </script>
      </head>
      <body>
      </body>
    </html>
    """
  end
end
