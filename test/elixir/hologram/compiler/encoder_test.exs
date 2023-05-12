defmodule Hologram.Compiler.EncoderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR

  test "atom type" do
    assert encode(%IR.AtomType{value: :"aa'bb\ncc"}) == "{type: 'atom', value: 'aa\\'bb\\ncc'}"
  end

  test "float type" do
    assert encode(%IR.FloatType{value: 1.23}) == "{type: 'float', value: 1.23}"
  end

  test "integer type" do
    assert encode(%IR.IntegerType{value: 123}) == "{type: 'integer', value: 123}"
  end

  describe "list type" do
    test "empty" do
      assert encode(%IR.ListType{data: []}) == "{type: 'list', data: []}"
    end

    test "non-empty" do
      ir = %IR.ListType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.AtomType{value: :abc}
        ]
      }

      assert encode(ir) ==
               "{type: 'list', data: [{type: 'integer', value: 1}, {type: 'atom', value: 'abc'}]}"
    end
  end

  describe "map type" do
    test "empty" do
      assert encode(%IR.MapType{data: []}) == "{type: 'map', data: {}}"
    end

    test "single key" do
      ir = %IR.MapType{
        data: [
          {
            %IR.AtomType{value: :a},
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir) == "{type: 'map', data: {'atom(a)': {type: 'integer', value: 1}}}"
    end

    test "multiple keys" do
      ir = %IR.MapType{
        data: [
          {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
          {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
        ]
      }

      assert encode(ir) ==
               "{type: 'map', data: {'atom(a)': {type: 'integer', value: 1}, 'atom(b)': {type: 'integer', value: 2}}}"
    end

    test "atom key" do
      ir = %IR.MapType{
        data: [
          {
            %IR.AtomType{value: :a},
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir) == "{type: 'map', data: {'atom(a)': {type: 'integer', value: 1}}}"
    end

    test "float key" do
      ir = %IR.MapType{
        data: [
          {
            %IR.FloatType{value: 1.23},
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir) == "{type: 'map', data: {'float(1.23)': {type: 'integer', value: 1}}}"
    end

    test "integer key" do
      ir = %IR.MapType{
        data: [
          {
            %IR.IntegerType{value: 987},
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir) == "{type: 'map', data: {'integer(987)': {type: 'integer', value: 1}}}"
    end

    test "list key, empty list" do
      ir = %IR.MapType{
        data: [
          {
            %IR.ListType{data: []},
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir) == "{type: 'map', data: {'list()': {type: 'integer', value: 1}}}"
    end

    test "list key, non-empty" do
      ir = %IR.MapType{
        data: [
          {
            %IR.ListType{
              data: [
                %IR.IntegerType{value: 1},
                %IR.AtomType{value: :abc}
              ]
            },
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir) ==
               "{type: 'map', data: {'list(integer(1),atom(abc))': {type: 'integer', value: 1}}}"
    end

    test "string key" do
      ir = %IR.MapType{
        data: [
          {
            %IR.StringType{value: "abc"},
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir) == "{type: 'map', data: {'string(abc)': {type: 'integer', value: 1}}}"
    end
  end

  test "string type" do
    assert encode(%IR.StringType{value: "aa'bb\ncc"}) == "{type: 'atom', value: 'aa\\'bb\\ncc'}"
  end

  describe "tuple type" do
    test "empty" do
      assert encode(%IR.TupleType{data: []}) == "{type: 'tuple', data: []}"
    end

    test "non-empty" do
      ir = %IR.TupleType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.AtomType{value: :abc}
        ]
      }

      assert encode(ir) ==
               "{type: 'tuple', data: [{type: 'integer', value: 1}, {type: 'atom', value: 'abc'}]}"
    end
  end
end
