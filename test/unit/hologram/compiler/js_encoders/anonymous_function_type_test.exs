defmodule Hologram.Compiler.JSEncoder.AnonymousFunctionTypeTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.{Context, JSEncoder, Opts}

  test "no vars / single expression" do
    code = "fn -> 1 end"
    ir = ir(code)
    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected = """
      (function() {
      return { type: 'integer', value: 1 };
      })\
      """

    assert result == expected
  end

  test "single var" do
    code = "fn x -> 1 end"
    ir = ir(code)
    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected = """
      (function() {
      let x = arguments[0];
      return { type: 'integer', value: 1 };
      })\
      """

    assert result == expected
  end

  test "multiple vars" do
    code = "fn x, y -> 1 end"
    ir = ir(code)
    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected = """
      (function() {
      let x = arguments[0];
      let y = arguments[1];
      return { type: 'integer', value: 1 };
      })\
      """

    assert result == expected
  end

  test "multiple expressions" do
    code = """
    fn ->
      1
      2
    end
    """

    ir = ir(code)
    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected = """
      (function() {
      { type: 'integer', value: 1 };
      return { type: 'integer', value: 2 };
      })\
      """

    assert result == expected
  end

  test "bindings from args are taken into account in block scope" do
    code = """
      fn x ->
        x = 2
        3
      end
      """

    ir = ir(code)
    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected = """
      (function() {
      let x = arguments[0];
      x = { type: 'integer', value: 2 };
      return { type: 'integer', value: 3 };
      })\
      """

    assert result == expected
  end
end
