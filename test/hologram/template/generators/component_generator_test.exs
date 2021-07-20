defmodule Hologram.Template.ComponentGeneratorTest do
  use Hologram.TestCase, async: true
  alias Hologram.Template.ComponentGenerator

  test "generate/1" do
    module = Hologram.Test.Fixtures.Template.ComponentGenerator.Module1

    result = ComponentGenerator.generate(module)
    expected = "{ type: 'component', module: 'Hologram.Test.Fixtures.Template.ComponentGenerator.Module1', children: [{ type: 'element', tag: 'div', attrs: {}, children: [{ type: 'text', content: 'test' }] }] }"

    assert result == expected
  end
end
