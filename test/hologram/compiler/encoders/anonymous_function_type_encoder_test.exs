defmodule Hologram.Compiler.AnonymousFunctionTypeEncoderTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.{Context, Encoder, Opts}

  test "no vars / single expression" do
    code = "fn -> 1 end"
    ir = ir(code)

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "(function() { return { type: 'integer', value: 1 }; })"

    assert result == expected
  end

  test "single var" do
    code = "fn x -> 1 end"
    ir = ir(code)

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "(function() { let x = arguments[0]; return { type: 'integer', value: 1 }; })"

    assert result == expected
  end

  test "multiple vars" do
    code = "fn x, y -> 1 end"
    ir = ir(code)

    result = Encoder.encode(ir, %Context{}, %Opts{})

    expected =
      "(function() { let x = arguments[0]; let y = arguments[1]; return { type: 'integer', value: 1 }; })"

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

    result = Encoder.encode(ir, %Context{}, %Opts{})

    expected =
      "(function() { { type: 'integer', value: 1 }; return { type: 'integer', value: 2 }; })"

    assert result == expected
  end
end
