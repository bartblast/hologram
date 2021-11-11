defmodule Hologram.Compiler.ResolverTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Resolver}
  alias Hologram.Compiler.IR.{AliasDirective, ImportDirective}

  @calling_module Hologram.Compiler.ResolverTest

  describe "resolve/5" do
    test "imported module" do
      imported_module = Hologram.Test.Fixtures.Compiler.Resolver.Module1
      imports = [%ImportDirective{module: imported_module}]
      context = %Context{module: @calling_module, imports: imports}

      result = Resolver.resolve([], :test, 2, context)
      assert result == imported_module
    end

    test "calling module public function" do
      context = %Context{module: @calling_module}

      result = Resolver.resolve([], :test, 2, context)
      assert result == @calling_module
    end

    test "calling module private function" do
      calling_module = Hologram.Test.Fixtures.Compiler.Resolver.Module2
      context = %Context{module: calling_module}

      result = Resolver.resolve([], :test, 2, context)
      assert result == calling_module
    end

    test "Kernel function" do
      context = %Context{module: @calling_module}
      result = Resolver.resolve([], :max, 2, context)

      assert result == Kernel
    end

    test "Kernel macro" do
      context = %Context{module: @calling_module}
      result = Resolver.resolve([], :to_string, 1, context)

      assert result == Kernel
    end

    test "aliased module" do
      aliased_module = Hologram.Test.Fixtures.Compiler.Resolver.Module1
      aliases = [%AliasDirective{module: aliased_module, as: [:Module1]}]
      context = %Context{module: @calling_module, aliases: aliases}

      result = Resolver.resolve([:Module1], :test, 2, context)

      assert result == aliased_module
    end

    test "vertbatim module" do
      context = %Context{module: @calling_module}
      verbatim_module = [:Hologram, :Test, :Fixtures, :Compiler, :Resolver, :Module1]
      result = Resolver.resolve(verbatim_module, :test, 2, context)

      assert result == Hologram.Test.Fixtures.Compiler.Resolver.Module1
    end
  end

  test "resolve/2" do
    aliased_module = Hologram.Test.Fixtures.Compiler.Resolver.Module1
    aliases = [%AliasDirective{module: aliased_module, as: [:Module1]}]
    context = %Context{aliases: aliases}
    result = Resolver.resolve([:Module1], context)

    assert result == aliased_module
  end
end
