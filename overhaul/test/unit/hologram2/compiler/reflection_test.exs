defmodule Hologram.Compiler.ReflectionTest do
  use Hologram.Test.BasicCase, async: true
  alias Hologram.Compiler.Reflection

  describe "is_alias?/1" do
    test "atom which is an alias" do
      assert Reflection.is_alias?(Calendar.ISO)
    end

    test "atom which is not an alias" do
      refute Reflection.is_alias?(:abc)
    end

    test "non-atom" do
      refute Reflection.is_alias?(123)
    end
  end
end
