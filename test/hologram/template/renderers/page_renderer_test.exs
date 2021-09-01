defmodule Hologram.Template.PageRendererTest do
  use Hologram.TestCase, async: false
  alias Hologram.Template.Renderer

  setup_all do
    # When compile_pages/1 test helper is used the router is recompiled with the pages found in the given pages_path.
    # After the tests, the router needs to be recompiled with the default pages_path.
    # Also, in such case the tests need to be non-async.
    on_exit(&compile_pages/0)
  end

  test "render/2" do
    compile_pages("test/fixtures/template/renderers/page_renderer")

    module = Hologram.Test.Fixtures.Template.PageRenderer.Module1
    result = Renderer.render(module, %{})

    expected =
      """
      <!DOCTYPE html>
      <html>
        <head>
          <title>Hologram Demo</title>
          <script src="/js/hologram.js"></script>
          <script src="/hologram/page-6f56263e38be28e0045ad607eeb9c4c4.js"></script>
          <script>
            Hologram.run(window, Elixir_Hologram_Test_Fixtures_Template_PageRenderer_Module1, "{ type: 'map', data: { '~atom[a]': { type: 'integer', value: 123 }, '~atom[context]': { type: 'map', data: { '~atom[__class__]': { type: 'string', value: 'Elixir_Hologram_Test_Fixtures_Template_PageRenderer_Module1' }, '~atom[__src__]': { type: 'string', value: '/hologram/page-6f56263e38be28e0045ad607eeb9c4c4.js' } } } } }")
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
