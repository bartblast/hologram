defmodule Hologram.Compiler.JSEncoder.BlockTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{AtomType, Block, IntegerType, MatchOperator, Variable}

  test "single expression" do
    ir = %Block{expressions: [%AtomType{value: :a}]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "return { type: 'atom', value: 'a' };"

    assert result == expected
  end

  test "multiple expressions / block ending with expression other than match operator" do
    ir = %Block{expressions: [
      %AtomType{value: :a},
      %AtomType{value: :b}
    ]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected = """
    { type: 'atom', value: 'a' };
    return { type: 'atom', value: 'b' };\
    """

    assert result == expected
  end

  test "bindings in block scope are kept track of" do
    # code:
    # x = 1
    # x = 2
    # 3

    ir = %Block{expressions: [
      %MatchOperator{
        bindings: [%Hologram.Compiler.IR.Binding{name: :x, access_path: []}],
        left: %Variable{name: :x},
        right: %IntegerType{value: 1}
      },
      %MatchOperator{
        bindings: [%Hologram.Compiler.IR.Binding{name: :x, access_path: []}],
        left: %Variable{name: :x},
        right: %IntegerType{value: 2}
      },
      %IntegerType{value: 3}
    ]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected = """
    window.hologramExpressionRightHandSide = { type: 'integer', value: 1 };
    let x = window.hologramExpressionRightHandSide;
    window.hologramExpressionRightHandSide = { type: 'integer', value: 2 };
    x = window.hologramExpressionRightHandSide;
    return { type: 'integer', value: 3 };\
    """

    assert result == expected
  end

  test "block ending with match operator expression" do
    ir = %Block{expressions: [
      %AtomType{value: :a},
      %MatchOperator{
        bindings: [%Hologram.Compiler.IR.Binding{name: :x, access_path: []}],
        left: %Variable{name: :x},
        right: %IntegerType{value: 1}
      },
    ]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected = """
    { type: 'atom', value: 'a' };
    window.hologramExpressionRightHandSide = { type: 'integer', value: 1 };
    let x = window.hologramExpressionRightHandSide;
    return window.hologramExpressionRightHandSide;\
    """

    assert result == expected
  end
end
