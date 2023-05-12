defmodule Hologram.Compiler.EncoderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR

  describe "encode/1" do
    test "atom type" do
      assert encode(%IR.AtomType{value: :"aa'bb\ncc"}) == "{type: 'atom', value: 'aa\\'bb\\ncc'}"
    end

    test "float type" do
      assert encode(%IR.FloatType{value: 1.23}) == "{type: 'float', value: 1.23}"
    end

    test "integer type" do
      assert encode(%IR.IntegerType{value: 123}) == "{type: 'integer', value: 123}"
    end

    test "list type, empty" do
      assert encode(%IR.ListType{data: []}) == "{type: 'list', data: []}"
    end

    test "list type, non-empty" do
      ir = %IR.ListType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.AtomType{value: :abc}
        ]
      }

      assert encode(ir) ==
               "{type: 'list', data: [{type: 'integer', value: 1}, {type: 'atom', value: 'abc'}]}"
    end

    test "string type" do
      assert encode(%IR.StringType{value: "aa'bb\ncc"}) == "{type: 'atom', value: 'aa\\'bb\\ncc'}"
    end

    test "tuple type, empty" do
      assert encode(%IR.TupleType{data: []}) == "{type: 'tuple', data: []}"
    end

    test "tuple type, non-empty" do
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

  describe "encode_as_string/1" do
    assert encode_as_string("aa'bb\ncc") == "'aa\\'bb\\ncc'"
  end
end
