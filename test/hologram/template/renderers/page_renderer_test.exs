defmodule Hologram.Template.PageRendererTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.Renderer
  alias Mix.Tasks.Compile.Hologram, as: Task

  test "render/2" do
    Task.run(pages_path: "test/fixtures/template/renderers/page_renderer")

    module = Hologram.Test.Fixtures.Template.PageRenderer.Module1
    result = Renderer.render(module, %{})

    expected =
      """
      <!DOCTYPE html>
      <html>
        <head>
          <title>Hologram Demo</title>
          <script src="/js/hologram.js"></script>
          <script src="/hologram/page-6b852779c06374d754ee658116cbc197.js"></script>
          <script>
            Hologram.run(window, Elixir_Hologram_Test_Fixtures_Template_PageRenderer_Module1, { type: 'map', data: { '~atom[a]': { type: 'integer', value: 123 } } })
          </script>
        </head>
        <body>
          <div>test template 123</div>
        </body>
      </html>\
      """

    assert result == expected
  end
end
