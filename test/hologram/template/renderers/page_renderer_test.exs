defmodule Hologram.Template.PageRendererTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.Reflection
  alias Hologram.Template.Renderer

  setup_all do
    on_exit(&compile_pages/0)
  end

  test "render/2" do
    compile_pages("test/fixtures/template/renderers/page_renderer")

    module = Hologram.Test.Fixtures.Template.PageRenderer.Module1
    digest = Reflection.get_page_digest(module)

    result = Renderer.render(module, %{})

    expected = """
    <!DOCTYPE html>
    <html>
      <head>
        <title>Hologram E2E</title>
        <script src="/hologram/runtime.js"></script>
    <script src="/hologram/page-#{digest}.js"></script>
    <script>
      Hologram.run(window, Elixir_Hologram_Test_Fixtures_Template_PageRenderer_Module1, "{ type: 'map', data: { '~atom[a]': { type: 'integer', value: 123 }, '~atom[context]': { type: 'map', data: { '~atom[__class__]': { type: 'string', value: 'Elixir_Hologram_Test_Fixtures_Template_PageRenderer_Module1' }, '~atom[__src__]': { type: 'string', value: '/hologram/page-#{digest}.js' } } } } }")
    </script>
      </head>
      <body>
        default layout:
        <div>test template 123</div>
      </body>
    </html>\
    """

    assert result == expected
  end
end
