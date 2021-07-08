defmodule Hologram.Template.ComponentGeneratorTest do
  use Hologram.TestCase, async: true
  alias Hologram.Template.ComponentGenerator

  test "generate/1" do
    module = [:Abc, :Bcd]

    result = ComponentGenerator.generate(module)
    expected = "{ type: 'component', module: 'Abc.Bcd' }"

    assert result == expected
  end
end
