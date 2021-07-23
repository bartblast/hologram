defmodule Hologram.Compiler.TypeOperatorTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, TypeOperatorTransformer}
  alias Hologram.Compiler.IR.{TypeOperator, Variable}

  @context %Context{
    module: nil,
    uses: [],
    imports: [],
    aliases: [],
    attributes: []
  }

  test "transform/2" do
    code = "str::binary"
    {:"::", _, ast} = ast(code)

    result = TypeOperatorTransformer.transform(ast, @context)

    expected =
      %TypeOperator{
        left: %Variable{name: :str},
        right: :binary
      }
  end
end
