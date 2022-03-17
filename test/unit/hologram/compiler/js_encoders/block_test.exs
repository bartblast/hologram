defmodule Hologram.Compiler.JSEncoder.BlockTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{AtomType, Binding, Block, IntegerType, MatchAccess, MatchOperator, Variable}

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
        bindings: [
          %Binding{name: :x, access_path: [%MatchAccess{}]}
        ],
        left: %Variable{name: :x},
        right: %IntegerType{value: 1}
      },
      %MatchOperator{
        bindings: [
          %Binding{name: :x, access_path: [%MatchAccess{}]}
        ],
        left: %Variable{name: :x},
        right: %IntegerType{value: 2}
      },
      %IntegerType{value: 3}
    ]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected = """
    window.$hologramMatchAccess = { type: 'integer', value: 1 };
    let x = window.$hologramMatchAccess;
    window.$hologramMatchAccess = { type: 'integer', value: 2 };
    x = window.$hologramMatchAccess;
    return { type: 'integer', value: 3 };\
    """

    assert result == expected
  end

  test "block ending with match operator expression" do
    ir = %Block{expressions: [
      %AtomType{value: :a},
      %MatchOperator{
        bindings: [
          %Binding{name: :x, access_path: [%MatchAccess{}]}
        ],
        left: %Variable{name: :x},
        right: %IntegerType{value: 1}
      },
    ]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected = """
    { type: 'atom', value: 'a' };
    window.$hologramMatchAccess = { type: 'integer', value: 1 };
    let x = window.$hologramMatchAccess;
    return window.$hologramMatchAccess;\
    """

    assert result == expected
  end
end
