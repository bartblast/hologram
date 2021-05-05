defmodule Hologram.Compiler.ResolverTest do
  use ExUnit.Case, async: true

  alias Hologram.Compiler.AST.Alias
  alias Hologram.Compiler.Resolver

  describe "resolve_aliased_module/2" do
    @aliases [
      %Alias{module: [:Abc, :Bcd], as: [:Bcd]},
      %Alias{module: [:Bcd, :Cde], as: [:Cde]}
    ]

    test "resolved" do
      result = Resolver.resolve_aliased_module([:Cde], @aliases)
      assert result == [:Bcd, :Cde]
    end

    test "not resolved" do
      result = Resolver.resolve_aliased_module([:Xyz], @aliases)
      refute result
    end
  end
end
