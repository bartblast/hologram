defmodule Hologram.Template.ComponentGeneratorTest do
  use Hologram.TestCase, async: true
  alias Hologram.Template.ComponentGenerator

  test "generate/1" do
    module = Hologram.Test.Fixtures.Template.ComponentGenerator.Module1

    result = ComponentGenerator.generate(module)
    expected_module = "Elixir_Hologram_Test_Fixtures_Template_ComponentGenerator_Module1"
    expected = "{ type: 'component', module: '#{expected_module}', children: [{ type: 'element', tag: 'div', attrs: {}, children: [{ type: 'text', content: 'test' }] }] }"

    assert result == expected
  end
end
