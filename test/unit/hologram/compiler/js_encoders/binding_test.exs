defmodule Hologram.Compiler.JSEncoder.BindingTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{AtomType, Binding, MapAccess, ParamAccess, VariableAccess}

  test "map access" do
    ir = %Binding{access_path: [%MapAccess{key: %AtomType{value: :x}}], name: :abc}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = .data['~atom[x]'];"

    assert result == expected
  end

  test "param access" do
    ir = %Binding{access_path: [%ParamAccess{index: 2}], name: :abc}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = arguments[2];"

    assert result == expected
  end

  test "variable access" do
    ir = %Binding{access_path: [%VariableAccess{name: :x}], name: :abc}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = x;"

    assert result == expected
  end

  test "multiple parts" do
    ir = %Binding{
      access_path: [
        %ParamAccess{index: 2},
        %MapAccess{key: %AtomType{value: :x}}
      ],
      name: :abc
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = arguments[2].data['~atom[x]'];"

    assert result == expected
  end
end
