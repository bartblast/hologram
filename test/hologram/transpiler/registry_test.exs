defmodule Hologram.Transpiler.RegistryTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.Function
  alias Hologram.Transpiler.Registry

  @registry %{
    [:Abc, :Bcd] => [
      %Function{name: :test_1, arity: 1},
      %Function{name: :test_2, arity: 1},
      %Function{name: :test_2, arity: 2},
      %Function{name: :test_3, arity: 3}
    ]
  }

  describe "has_function?/4" do
    test "name not matched, arity not matched" do
      refute Registry.has_function?(@registry, [:Abc, :Bcd], :test_4, 4)
    end

    test "name matched, arity not matched" do
      refute Registry.has_function?(@registry, [:Abc, :Bcd], :test_2, 4)
    end

    test "name not matched, arity matched" do
      refute Registry.has_function?(@registry, [:Abc, :Bcd], :test_4, 1)
    end

    test "name matched, arity matched" do
      assert Registry.has_function?(@registry, [:Abc, :Bcd], :test_2, 2)
    end

    test "invalid module" do
      refute Registry.has_function?(@registry, [:Abc, :Xyz], :test_2, 2)
    end
  end
end
