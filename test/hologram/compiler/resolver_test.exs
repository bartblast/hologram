defmodule Hologram.Compiler.ResolverTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{Alias, Import}
  alias Hologram.Compiler.Resolver

  describe "resolve/5" do
    test "imported module" do
      imported_module = [:Hologram, :Test, :Fixtures, :Compiler, :Resolver, :Module1]
      imports = [%Import{module: imported_module}]

      result = Resolver.resolve([], :test, 2, imports, [], [:Hologram, :Compiler, :ResolverTest])
      assert result == imported_module
    end

    test "calling module" do
      calling_module = [:Hologram, :Test, :Fixtures, :Compiler, :Resolver, :Module1]

      result = Resolver.resolve([], :test, 2, [], [], calling_module)
      assert result == calling_module
    end

    test "Kernel" do
      result = Resolver.resolve([], :to_string, 1, [], [], [:Hologram, :Compiler, :ResolverTest])
      assert result == [:Kernel]
    end

    test "aliased module" do
      aliased_module = [:Hologram, :Test, :Fixtures, :Compiler, :Resolver, :Module1]
      aliases = [%Alias{module: aliased_module, as: [:Module1]}]

      result =
        Resolver.resolve([:Module1], :test, 2, [], aliases, [:Hologram, :Compiler, :ResolverTest])

      assert result == aliased_module
    end

    test "vertbatim module" do
      verbatim_module = [:Abc, :Bcd]

      result =
        Resolver.resolve(verbatim_module, :test, 2, [], [], [:Hologram, :Compiler, :ResolverTest])

      assert result == verbatim_module
    end
  end

  test "resolve/2" do
    aliased_module = [:Hologram, :Test, :Fixtures, :Compiler, :Resolver, :Module1]
    aliases = [%Alias{module: aliased_module, as: [:Module1]}]

    result = Resolver.resolve([:Module1], aliases)
    assert result == aliased_module
  end
end
