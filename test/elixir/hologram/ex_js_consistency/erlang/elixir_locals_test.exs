defmodule Hologram.ExJsConsistency.Erlang.ElixirLocalsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/elixir_locals_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  if Version.match?(System.version(), "< 1.18.0") do
    describe "yank/2" do
      test "returns the removed value and updated locals as a tuple" do
        locals = %{a: 1, b: 2}

        assert :elixir_locals.yank(locals, :b) == {2, %{a: 1}}
      end

      test "returns :error when the key is not present" do
        locals = %{a: 1}

        assert :elixir_locals.yank(locals, :b) == :error
      end

      test "raises BadMapError when the first argument is not a map" do
        assert_error BadMapError, "expected a map, got: :x", fn ->
          :elixir_locals.yank(:x, :b)
        end
      end
    end
  end
end
