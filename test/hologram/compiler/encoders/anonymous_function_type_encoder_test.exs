defmodule Hologram.Compiler.AnonymousFunctionTypeEncoderTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.{Context, Encoder, Opts}

  test "no args, no vars, only return statement" do
    code = "fn -> 1 end"
    ir = ir(code)

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "(function() { return { type: 'integer', value: 1 }; })"

    assert result == expected
  end

  test "has args, has vars, variable access" do
    code = "fn x -> 1 end"
    ir = ir(code)

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "(function() { let x = arguments[0]; return { type: 'integer', value: 1 }; })"

    assert result == expected
  end

  test "map access, expression + return statement" do
    code = """
    fn %{a: x} ->
      1
      2
    end
    """

    ir = ir(code)

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "(function() { let x = arguments[0].data['~atom[a]']; { type: 'integer', value: 1 }; return { type: 'integer', value: 2 }; })"

    assert result == expected
  end
end
