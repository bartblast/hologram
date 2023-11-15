defmodule Hologram.ExJsConsistency.Elixir.KernelTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/elixir/kernel_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  describe "inspect/1" do
    test "delegates to inspect/2" do
      assert Kernel.inspect(true) == "true"
    end
  end

  # Important: keep Interpreter.inspect() consistency tests in sync.
  describe "inspect/2" do
    test "atom, true" do
      assert Kernel.inspect(true, []) == "true"
    end

    test "atom, false" do
      assert Kernel.inspect(false, []) == "false"
    end

    test "atom, nil" do
      assert Kernel.inspect(nil, []) == "nil"
    end

    test "atom, non-boolean and non-nil" do
      assert Kernel.inspect(:abc, []) == ":abc"
    end

    test "bitstring, empty text" do
      assert Kernel.inspect("", []) == ~s'""'
    end

    test "bitstring, ASCII text" do
      assert Kernel.inspect("abc", []) == ~s'"abc"'
    end

    test "bitstring, Unicode text" do
      assert Kernel.inspect("全息图", []) == ~s'"全息图"'
    end

    test "float, integer-representable" do
      assert Kernel.inspect(123.0, []) == "123.0"
    end

    test "float, not integer-representable" do
      assert Kernel.inspect(123.45, []) == "123.45"
    end

    test "integer" do
      assert Kernel.inspect(123, []) == "123"
    end

    test "list, empty" do
      assert Kernel.inspect([], []) == "[]"
    end

    test "list, non-empty, proper" do
      assert Kernel.inspect([1, 2, 3], []) == "[1, 2, 3]"
    end

    test "list, non-empty, improper" do
      assert Kernel.inspect([1, 2 | 3], []) == "[1, 2 | 3]"
    end

    # Same as "bitstring".
    # test "string"

    test "tuple, empty" do
      assert Kernel.inspect({}, []) == "{}"
    end

    test "tuple, non-empty" do
      assert Kernel.inspect({1, 2, 3}, []) == "{1, 2, 3}"
    end
  end
end
