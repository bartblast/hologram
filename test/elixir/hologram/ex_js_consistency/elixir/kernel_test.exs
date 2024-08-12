defmodule Hologram.ExJsConsistency.Elixir.KernelTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/elixir/kernel_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  def my_local_fun(x, y) do
    x + y * x
  end

  describe "inspect/1" do
    test "delegates to inspect/2" do
      assert Kernel.inspect(true) == "true"
    end
  end

  # Important: keep Interpreter.inspect() consistency tests in sync.
  describe "inspect/2" do
    # Client result for non-capture anonymous function is intentionally different than server result.
    test "anonymous function, non-capture" do
      anon_fun = fn x, y -> x + y * x end

      Kernel.inspect(anon_fun, []) =~
        ~r'#Function<[0-9]+\.[0-9]/2 in Hologram\.ExJsConsistency\.Elixir\.KernelTest\."test inspect/2 anonymous function, non-capture"/1>'
    end

    test "anonymous function, local function capture" do
      assert Kernel.inspect(&my_local_fun/2, []) =~
               ~r'^#Function<[0-9]+\.[0-9]+/2 in Hologram\.ExJsConsistency\.Elixir\.KernelTest\.my_local_fun>$'
    end

    test "anonymous function, remote function capture" do
      assert Kernel.inspect(&DateTime.now/2) == "&DateTime.now/2"
    end

    test "atom, true" do
      assert Kernel.inspect(true, []) == "true"
    end

    test "atom, false" do
      assert Kernel.inspect(false, []) == "false"
    end

    test "atom, nil" do
      assert Kernel.inspect(nil, []) == "nil"
    end

    test "atom, module alias" do
      assert Kernel.inspect(Aaa.Bbb, []) == "Aaa.Bbb"
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

    test "bitstring, not text" do
      assert Kernel.inspect(<<0b11001100, 0b10101010, 0b11::size(2)>>) ==
               "<<204, 170, 3::size(2)>>"
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

    test "map, empty" do
      assert Kernel.inspect(%{}, []) == "%{}"
    end

    test "map, non-empty, with atom keys" do
      assert Kernel.inspect(%{a: 1, b: "xyz"}, []) in [
               ~s'%{a: 1, b: "xyz"}',
               ~s'%{b: "xyz", a: 1}'
             ]
    end

    test "map, non-empty, with non-atom keys" do
      assert Kernel.inspect(%{9 => "xyz", "abc" => 2.3}, []) == ~s'%{9 => "xyz", "abc" => 2.3}'
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
