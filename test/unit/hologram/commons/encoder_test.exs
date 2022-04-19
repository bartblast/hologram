defmodule Hologram.Commons.EncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Commons.Encoder
  alias Hologram.Compiler.{Context, Opts}
  alias Hologram.Compiler.IR.{AtomType, Block, IntegerType}

  describe "encode_as_anonymous_function/3" do
    test "block" do
      body = %Block{
        expressions: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }

      result = Encoder.encode_as_anonymous_function(body, %Context{}, %Opts{})

      expected = """
      () => {
      { type: 'integer', value: 1 };
      return { type: 'integer', value: 2 };
      }\
      """

      assert result == expected
    end

    test "single expression" do
      expr = %IntegerType{value: 1}
      result = Encoder.encode_as_anonymous_function(expr, %Context{}, %Opts{})

      expected = """
      () => {
      return { type: 'integer', value: 1 };
      }\
      """

      assert result == expected
    end
  end

  describe "encode_as_array/3" do
    test "empty list encoding" do
      data = []
      result = Encoder.encode_as_array(data, %Context{}, %Opts{})

      assert result == "[]"
    end

    test "non-empty list encoding" do
      data = [%IntegerType{value: 1}, %IntegerType{value: 2}]
      result = Encoder.encode_as_array(data, %Context{}, %Opts{})
      expected = "[ { type: 'integer', value: 1 }, { type: 'integer', value: 2 } ]"

      assert result == expected
    end
  end

  describe "encode_expression/4" do
    test "single expression" do
      body = [%IntegerType{value: 1}]

      result = Encoder.encode_expressions(body, %Context{}, %Opts{}, "\n")
      expected = "return { type: 'integer', value: 1 };"

      assert result == expected
    end

    test "multiple expressions" do
      body = [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]

      result = Encoder.encode_expressions(body, %Context{}, %Opts{}, "\n")
      expected = "{ type: 'integer', value: 1 };\nreturn { type: 'integer', value: 2 };"

      assert result == expected
    end
  end

  describe "encode_identifier/1" do
    test "string" do
      result = Encoder.encode_identifier("test")
      assert result == "test"
    end

    test "atom" do
      result = Encoder.encode_identifier(:test)
      assert result == "test"
    end

    test "question mark" do
      result = Encoder.encode_identifier("test?")
      assert result == "test$question"
    end

    test "exclamation mark" do
      result = Encoder.encode_identifier("test!")
      assert result == "test$bang"
    end
  end

  describe "encode_map_data/3" do
    test "empty data" do
      data = []

      result = Encoder.encode_map_data(data, %Context{}, %Opts{})
      expected = "{}"

      assert result == expected
    end

    test "non-empty data" do
      data = [
        {%AtomType{value: :a}, %IntegerType{value: 1}},
        {%AtomType{value: :b}, %IntegerType{value: 2}}
      ]

      result = Encoder.encode_map_data(data, %Context{}, %Opts{})

      expected =
        "{ '~atom[a]': { type: 'integer', value: 1 }, '~atom[b]': { type: 'integer', value: 2 } }"

      assert result == expected
    end
  end

  test "encode_primitive_key/2" do
    result = Encoder.encode_primitive_key(:atom, :test)
    assert result == "~atom[test]"
  end

  test "encode_primitive_type/2" do
    result = Encoder.encode_primitive_type(:atom, "'test'")
    assert result == "{ type: 'atom', value: 'test' }"
  end

  test "encode_vars/3" do
    code = "fn x, %{a: y} -> 1 end"
    %{bindings: bindings} = ir(code)

    result = Encoder.encode_vars(bindings, %Context{}, %Opts{})

    expected = """
    let x = arguments[0];
    let y = arguments[1].data['~atom[a]'];\
    """

    assert result == expected
  end

  describe "wrap_with_array/1" do
    test "empty data" do
      assert Encoder.wrap_with_array("") == "[]"
    end

    test "non-empty data" do
      assert Encoder.wrap_with_array("test") == "[ test ]"
    end
  end

  describe "wrap_with_object/1" do
    test "empty data" do
      assert Encoder.wrap_with_object("") == "{}"
    end

    test "non-empty data" do
      assert Encoder.wrap_with_object("test") == "{ test }"
    end
  end
end
