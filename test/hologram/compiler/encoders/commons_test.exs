defmodule Hologram.Compiler.Encoder.CommonsTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, Opts}
  alias Hologram.Compiler.Encoder.Commons
  alias Hologram.Compiler.IR.IntegerType

  test "single expression" do
    body = [%IntegerType{value: 1}]

    result = Commons.generate_expressions(body, %Context{}, %Opts{}, "\n")
    expected = "return { type: 'integer', value: 1 };"

    assert result == expected
  end

  test "multiple expressions" do
    body = [
      %IntegerType{value: 1},
      %IntegerType{value: 2}
    ]

    result = Commons.generate_expressions(body, %Context{}, %Opts{}, "\n")
    expected = "{ type: 'integer', value: 1 };\nreturn { type: 'integer', value: 2 };"

    assert result == expected
  end
end
