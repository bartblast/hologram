defmodule Hologram.Compiler.Encoder.CommonsTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, Opts}
  alias Hologram.Compiler.Encoder.Commons
  alias Hologram.Compiler.IR.IntegerType

  describe "generate_expression/4" do
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

  describe "generate_vars/3" do
    test "single binding / variable" do
      code = "fn x -> 1 end"
      %{bindings: bindings} = ir(code)

      result = Commons.generate_vars(bindings, %Context{}, "\n")
      expected = "let x = arguments[0];"

      assert result == expected
    end

    test "multiple bindings" do
      code = "fn x, y -> 1 end"
      %{bindings: bindings} = ir(code)

      result = Commons.generate_vars(bindings, %Context{}, "\n")
      expected = "let x = arguments[0];\nlet y = arguments[1];"

      assert result == expected
    end

    test "access operator" do
      code = "fn %{a: x} -> 1 end"
      %{bindings: bindings} = ir(code)

      result = Commons.generate_vars(bindings, %Context{}, "\n")
      expected = "let x = arguments[0].data['~atom[a]'];"

      assert result == expected
    end
  end
end
