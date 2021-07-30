defmodule Hologram.Template.EvaluatorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{FunctionCall, IntegerType, ListType, ModuleAttributeOperator}
  alias Hologram.Template.Evaluator

  @state %{}

  describe "types" do
    test "integer" do
      ir = %IntegerType{value: 123}

      result = Evaluator.evaluate(ir, @state)
      expected = 123

      assert result == expected
    end

    test "list" do
      ir = %ListType{
        data: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
        ]
      }

      result = Evaluator.evaluate(ir, @state)
      expected = [1, 2]

      assert result == expected
    end
  end

  describe "operators" do
    test "module attribute" do
      ir = %ModuleAttributeOperator{name: :a}
      state = %{a: 123}

      result = Evaluator.evaluate(ir, state)
      expected = 123

      assert result == expected
    end
  end
end
