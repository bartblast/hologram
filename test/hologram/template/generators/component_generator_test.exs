defmodule Hologram.Template.ComponentGeneratorTest do
  use Hologram.TestCase, async: true
  alias Hologram.Template.ComponentGenerator

  test "generate/1" do
    module = [:Abc, :Bcd]
    context = []

    result = ComponentGenerator.generate(module, context)
    expected = "{ type: 'component', module: 'Abc.Bcd' }"

    assert result == expected
  end
end
