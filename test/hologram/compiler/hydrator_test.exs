defmodule Hologram.Compiler.HydratorTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.Hydrator

  test "hydrate/1" do
    state = %{a: 1, b: 2}

    result = Hydrator.hydrate(state)

    expected =
      "{ type: 'map', data: { '~atom[a]': { type: 'integer', value: 1 }, '~atom[b]': { type: 'integer', value: 2 } } }"

    assert result == expected
  end
end
