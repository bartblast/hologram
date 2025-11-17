defmodule Hologram.ExJsConsistency.Erlang.ElixirLocalsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/elixir_locals_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "yank/2" do
    test "returns the removed value and the map without the key" do
      locals = %{foo: 1}

      assert :elixir_locals.yank(locals, :foo) == {1, %{}}
    end

    test "returns :error when the key is not present" do
      locals = %{foo: 1}

      assert :elixir_locals.yank(locals, :bar) == :error
    end

    test "raises BadMapError when the first argument is not a map" do
      assert_error BadMapError, "expected a map, got: :abc", fn ->
        :elixir_locals.yank(:abc, :foo)
      end
    end
  end
end
