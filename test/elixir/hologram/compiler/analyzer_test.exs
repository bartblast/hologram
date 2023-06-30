defmodule Hologram.Compiler.AnalyzerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Analyzer

  alias Hologram.Compiler.Analyzer.Info
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR

  @context %Context{}

  @info %Info{
    var_patterns: MapSet.new([:m]),
    var_values: MapSet.new([:n])
  }

  test "variable pattern" do
    ir = %IR.Variable{name: :x}
    result = analyze(ir, %Context{pattern?: true}, @info)

    assert result == %Info{
             var_patterns: MapSet.new([:m, :x]),
             var_values: MapSet.new([:n])
           }
  end

  test "variable value" do
    ir = %IR.Variable{name: :x}
    result = analyze(ir, %Context{pattern?: false}, @info)

    assert result == %Info{
             var_patterns: MapSet.new([:m]),
             var_values: MapSet.new([:n, :x])
           }
  end

  test "match operator" do
    ir = %IR.MatchOperator{left: %IR.Variable{name: :x}, right: %IR.Variable{name: :y}}
    result = analyze(ir, @context, @info)

    assert result == %Info{
             var_patterns: MapSet.new([:m, :x]),
             var_values: MapSet.new([:n, :y])
           }
  end

  test "nested match operator" do
    ir = %IR.MatchOperator{
      left: %IR.Variable{name: :x},
      right: %IR.MatchOperator{left: %IR.Variable{name: :y}, right: %IR.Variable{name: :z}}
    }

    result = analyze(ir, @context, @info)

    assert result == %Info{
             var_patterns: MapSet.new([:m, :x, :y]),
             var_values: MapSet.new([:n, :z])
           }
  end

  test "list" do
    ir = %IR.ListType{
      data: [
        %IR.Variable{name: :a},
        %IR.MatchOperator{left: %IR.Variable{name: :b}, right: %IR.Variable{name: :c}},
        %IR.Variable{name: :d},
        %IR.MatchOperator{left: %IR.Variable{name: :e}, right: %IR.Variable{name: :f}}
      ]
    }

    result = analyze(ir, @context, @info)

    assert result == %Info{
             var_patterns: MapSet.new([:m, :b, :e]),
             var_values: MapSet.new([:n, :a, :c, :d, :f])
           }
  end

  test "map" do
    ir = %IR.MapType{
      data: [
        {%IR.Variable{name: :key_1}, %IR.Variable{name: :a}},
        {%IR.AtomType{value: :key_2},
         %IR.MatchOperator{left: %IR.Variable{name: :b}, right: %IR.Variable{name: :c}}},
        {%IR.AtomType{value: :key_3}, %IR.Variable{name: :d}},
        {%IR.Variable{name: :key_4},
         %IR.MatchOperator{left: %IR.Variable{name: :e}, right: %IR.Variable{name: :f}}}
      ]
    }

    result = analyze(ir, @context, @info)

    assert result == %Info{
             var_patterns: MapSet.new([:m, :b, :e]),
             var_values: MapSet.new([:n, :a, :c, :d, :f, :key_1, :key_4])
           }
  end

  test "tuple" do
    ir = %IR.TupleType{
      data: [
        %IR.Variable{name: :a},
        %IR.MatchOperator{left: %IR.Variable{name: :b}, right: %IR.Variable{name: :c}},
        %IR.Variable{name: :d},
        %IR.MatchOperator{left: %IR.Variable{name: :e}, right: %IR.Variable{name: :f}}
      ]
    }

    result = analyze(ir, @context, @info)

    assert result == %Info{
             var_patterns: MapSet.new([:m, :b, :e]),
             var_values: MapSet.new([:n, :a, :c, :d, :f])
           }
  end

  test "basic type" do
    ir = %IR.AtomType{value: :abc}
    result = analyze(ir, @context, @info)

    assert result == @info
  end
end
