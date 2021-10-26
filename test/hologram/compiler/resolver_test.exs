defmodule Hologram.Compiler.ResolverTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{AliasDirective, ImportDirective}
  alias Hologram.Compiler.Resolver

  describe "resolve/5" do
    test "imported module" do
      imported_module = Hologram.Test.Fixtures.Compiler.Resolver.Module1
      imports = [%ImportDirective{module: imported_module}]

      result = Resolver.resolve([], :test, 2, imports, [], Hologram.Compiler.ResolverTest)
      assert result == imported_module
    end

    test "calling module" do
      calling_module = Hologram.Test.Fixtures.Compiler.Resolver.Module1

      result = Resolver.resolve([], :test, 2, [], [], calling_module)
      assert result == calling_module
    end

    test "Kernel" do
      calling_module = Hologram.Compiler.ResolverTest
      result = Resolver.resolve([], :to_string, 1, [], [], calling_module)

      assert result == Kernel
    end

    test "aliased module" do
      aliased_module = Hologram.Test.Fixtures.Compiler.Resolver.Module1
      aliases = [%AliasDirective{module: aliased_module, as: [:Module1]}]
      calling_module = Hologram.Compiler.ResolverTest

      result = Resolver.resolve([:Module1], :test, 2, [], aliases, calling_module)

      assert result == aliased_module
    end

    test "vertbatim module" do
      verbatim_module = [:Hologram, :Test, :Fixtures, :Compiler, :Resolver, :Module1]

      result = Resolver.resolve(verbatim_module, :test, 2, [], [], Hologram.Compiler.ResolverTest)

      assert result == Hologram.Test.Fixtures.Compiler.Resolver.Module1
    end
  end

  test "resolve/2" do
    aliased_module = Hologram.Test.Fixtures.Compiler.Resolver.Module1
    aliases = [%AliasDirective{module: aliased_module, as: [:Module1]}]

    result = Resolver.resolve([:Module1], aliases)
    assert result == aliased_module
  end
end
