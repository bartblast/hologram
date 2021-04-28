defmodule Hologram.Transpiler.HydratorTest do
  use ExUnit.Case, async: true
  alias Hologram.Transpiler.Hydrator

  test "hydrate/1" do
    state = %{a: 1, b: 2}

    result = Hydrator.hydrate(state)

    expected =
      "{ type: 'map', data: { '~Hologram.Transpiler.AST.AtomType[a]': { type: 'integer', value: 1 }, '~Hologram.Transpiler.AST.AtomType[b]': { type: 'integer', value: 2 } } }"

    assert result == expected
  end
end
