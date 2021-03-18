defmodule Holograf.Transpiler.GeneratorTest do
  use ExUnit.Case

  alias Holograf.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Holograf.Transpiler.Generator

  describe "primitives" do
    test "atom" do
      result = Generator.generate(%AtomType{value: :test})
      assert result == "'test'"
    end

    test "boolean" do
      result = Generator.generate(%BooleanType{value: true})
      assert result == "true"
    end

    test "integer" do
      result = Generator.generate(%IntegerType{value: 123})
      assert result == "123"
    end

    test "string" do
      result = Generator.generate(%StringType{value: "Test"})
      assert result == "'Test'"
    end
  end
end
