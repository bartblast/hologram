defmodule Hologram.Compiler.JSEncoder.BindingTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{AtomType, Binding, MapAccess, ParamAccess, TupleAccess, VariableAccess}

  test "map access" do
    ir = %Binding{name: :abc, access_path: [%MapAccess{key: %AtomType{value: :x}}]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = .data['~atom[x]'];"

    assert result == expected
  end

  test "param access" do
    ir = %Binding{name: :abc, access_path: [%ParamAccess{index: 2}]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = arguments[2];"

    assert result == expected
  end

  test "tuple access" do
    ir = %Binding{name: :abc, access_path: [%TupleAccess{index: 2}]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = .data[2];"

    assert result == expected
  end

  test "variable access" do
    ir = %Binding{name: :abc, access_path: [%VariableAccess{name: :x}]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = x;"

    assert result == expected
  end

  test "multiple parts" do
    ir = %Binding{
      name: :abc,
      access_path: [
        %ParamAccess{index: 2},
        %MapAccess{key: %AtomType{value: :x}}
      ]
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = arguments[2].data['~atom[x]'];"

    assert result == expected
  end
end
