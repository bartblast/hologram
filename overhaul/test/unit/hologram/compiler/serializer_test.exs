defmodule Hologram.Compiler.SerializerTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.Serializer

  test "serialize/1" do
    state = %{a: 1, b: 2}

    result = Serializer.serialize(state)

    expected =
      "{ type: 'map', data: { '~atom[a]': { type: 'integer', value: 1 }, '~atom[b]': { type: 'integer', value: 2 } } }"

    assert result == expected
  end
end
