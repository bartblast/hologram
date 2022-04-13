defmodule Hologram.Compiler.JSEncoder.BindingTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Config, Context, JSEncoder, Opts}

  alias Hologram.Compiler.IR.{
    AtomType,
    Binding,
    CaseConditionAccess,
    ListIndexAccess,
    ListTailAccess,
    MapAccess,
    MatchAccess,
    ParamAccess,
    TupleAccess
  }

  @case_condition_js Config.case_condition_js()
  @match_access_js Config.match_access_js()

  test "case condition access" do
    ir = %Binding{name: :abc, access_path: [%CaseConditionAccess{}]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = #{@case_condition_js};"

    assert result == expected
  end

  test "list index access" do
    ir = %Binding{name: :abc, access_path: [%ParamAccess{index: 0}, %ListIndexAccess{index: 2}]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = arguments[0].data[2];"

    assert result == expected
  end

  test "list tail access" do
    ir = %Binding{name: :abc, access_path: [%ParamAccess{index: 0}, %ListTailAccess{}]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = Elixir_Kernel.tl(arguments[0]);"

    assert result == expected
  end

  test "map access" do
    ir = %Binding{name: :abc, access_path: [%ParamAccess{index: 0}, %MapAccess{key: %AtomType{value: :x}}]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = arguments[0].data['~atom[x]'];"

    assert result == expected
  end

  test "match access" do
    ir = %Binding{name: :abc, access_path: [%MatchAccess{}]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = #{Config.match_access_js()};"

    assert result == expected
  end

  test "param access" do
    ir = %Binding{name: :abc, access_path: [%ParamAccess{index: 2}]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = arguments[2];"

    assert result == expected
  end

  test "tuple access" do
    ir = %Binding{name: :abc, access_path: [%ParamAccess{index: 0}, %TupleAccess{index: 2}]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = arguments[0].data[2];"

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

  test "binding isn't in the block scope yet" do
    ir = %Binding{name: :abc, access_path: [%MatchAccess{}]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "let abc = #{@match_access_js};"

    assert result == expected
  end

  test "binding is already in the block scope" do
    ir = %Binding{name: :abc, access_path: [%MatchAccess{}]}

    context = %Context{block_bindings: [:abc]}
    result = JSEncoder.encode(ir, context, %Opts{})

    expected = "abc = #{@match_access_js};"

    assert result == expected
  end
end
