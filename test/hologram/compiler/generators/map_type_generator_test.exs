defmodule Hologram.Compiler.MapTypeGeneratorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, MapTypeGenerator, Opts}
  alias Hologram.Compiler.IR.{AtomType, IntegerType, MapType}

  test "generate/3" do
    ir = %MapType{data: [{%AtomType{value: :a}, %IntegerType{value: 1}}]}

    result = MapTypeGenerator.generate(ir.data, %Context{}, %Opts{})
    expected = "{ type: 'map', data: { '~atom[a]': { type: 'integer', value: 1 } } }"

    assert result == expected
  end

  describe "generate_data/3" do
    test "empty data" do
      data = []

      result = MapTypeGenerator.generate_data(data, %Context{}, %Opts{})
      expected = "{}"

      assert result == expected
    end

    test "non-empty data" do
      data = [
        {%AtomType{value: :a}, %IntegerType{value: 1}},
        {%AtomType{value: :b}, %IntegerType{value: 2}}
      ]

      result = MapTypeGenerator.generate_data(data, %Context{}, %Opts{})

      expected =
        "{ '~atom[a]': { type: 'integer', value: 1 }, '~atom[b]': { type: 'integer', value: 2 } }"

      assert result == expected
    end
  end
end
