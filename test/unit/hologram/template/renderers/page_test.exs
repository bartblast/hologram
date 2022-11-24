defmodule Hologram.Template.Renderer.PageTest do
  use Hologram.Test.UnitCase, async: false
  require Logger

  alias Hologram.Conn
  alias Hologram.Runtime
  alias Hologram.Runtime.PageDigestStore
  alias Hologram.Template.Renderer

  setup do
    Logger.debug("started setup")

    [
      app_path: "#{@fixtures_path}/template/renderers/page_renderer",
      templatables: [Hologram.Test.Fixtures.App.DefaultLayout]
    ]
    |> compile()

    Runtime.run()

    :ok
  end

  test "render/4" do
    Logger.debug("started test")

    module = Hologram.Test.Fixtures.Template.PageRenderer.Module1
    bindings = %{}

    conn = %Conn{
      params: %{
        c: 567
      },
      session: %{
        d: 345,
        e: 678
      }
    }

    result = Renderer.render(module, conn, bindings)

    digest = PageDigestStore.get!(module)
    assert digest =~ md5_hex_regex()

    expected = """
    <!DOCTYPE html>
    <html>
      <head>
        <script>
      window.hologramArgs = {
        class: "Elixir_Hologram_Test_Fixtures_Template_PageRenderer_Module1",
        digest: "#{digest}",
        state: { type: 'map', data: { '~atom[component_3_id]': { type: 'map', data: { '~atom[component_3_state_key]': { type: 'string', value: 'component_3_state_value' } } }, '~atom[layout]': { type: 'map', data: { '~atom[b]': { type: 'integer', value: 987 }, '~atom[e]': { type: 'integer', value: 678 } } }, '~atom[page]': { type: 'map', data: { '~atom[a]': { type: 'integer', value: 123 }, '~atom[c]': { type: 'integer', value: 567 }, '~atom[d]': { type: 'integer', value: 345 } } } } }
      }
    </script>
    <script src="/hologram/manifest.js"></script>
    <script src="/hologram/runtime.js"></script>
    <script src="/hologram/page-#{digest}.js"></script>
      </head>
      <body>
        layout template assign 987, layout template conn session 678
        page template assign 123, page template param 567, page template conn session 345
    (in component 3)
      </body>
    </html>\
    """

    assert result == expected
  end
end
