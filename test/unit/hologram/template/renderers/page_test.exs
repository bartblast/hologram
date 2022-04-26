defmodule Hologram.Template.Renderer.PageTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Conn
  alias Hologram.Runtime
  alias Hologram.Runtime.PageDigestStore
  alias Hologram.Template.Renderer

  setup do
    [
      app_path: "#{@fixtures_path}/template/renderers/page_renderer",
      templatables: [HologramE2E.DefaultLayout]
    ]
    |> compile()

    Runtime.run()

    :ok
  end

  test "render/4" do
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
        state: "{ type: 'map', data: { '~atom[a]': { type: 'integer', value: 123 }, '~atom[b]': { type: 'integer', value: 987 }, '~atom[c]': { type: 'integer', value: 567 }, '~atom[context]': { type: 'map', data: { '~atom[__class__]': { type: 'string', value: 'Elixir_Hologram_Test_Fixtures_Template_PageRenderer_Module1' }, '~atom[__digest__]': { type: 'string', value: '#{digest}' } } }, '~atom[d]': { type: 'integer', value: 345 }, '~atom[e]': { type: 'integer', value: 678 } } }"
      }
    </script>
    <script src="/hologram/manifest.js"></script>
    <script src="/hologram/runtime.js"></script>
    <script src="/hologram/page-#{digest}.js"></script>
      </head>
      <body>
        layout template assign 987, layout template conn session 678
        page template assign 123, page template param 567, page template conn session 345
      </body>
    </html>\
    """

    assert result == expected
  end
end
