defmodule Hologram.Template.Renderer.PageTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Runtime
  alias Hologram.Runtime.PageDigestStore
  alias Hologram.Template.Renderer

  test "render/2" do
    "#{File.cwd!()}/test/fixtures/template/renderers/page_renderer"
    |> compile_templatables()

    Runtime.reload()

    module = Hologram.Test.Fixtures.Template.PageRenderer.Module1
    digest = PageDigestStore.get(module)
    assert digest =~ uuid_hex_regex()

    result = Renderer.render(module, %{})

    expected = """
    <!DOCTYPE html>
    <html>
      <head>
        <script src="/hologram/manifest.js"></script>
    <script src="/hologram/runtime.js"></script>
    <script src="/hologram/page-b3c30aef343636aa19c36185d7589ed4.js"></script>
    <script>
      Hologram.run(Elixir_Hologram_Test_Fixtures_Template_PageRenderer_Module1, "{ type: 'map', data: { '~atom[a]': { type: 'integer', value: 123 }, '~atom[b]': { type: 'integer', value: 987 }, '~atom[context]': { type: 'map', data: { '~atom[__class__]': { type: 'string', value: 'Elixir_Hologram_Test_Fixtures_Template_PageRenderer_Module1' }, '~atom[__digest__]': { type: 'string', value: '#{digest}' } } } } }")
    </script>
      </head>
      <body>
        layout template 987
        page template 123
      </body>
    </html>\
    """

    assert result == expected
  end
end
