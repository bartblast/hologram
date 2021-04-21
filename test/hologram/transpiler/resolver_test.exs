defmodule Hologram.Transpiler.ResolverTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.Alias
  alias Hologram.Transpiler.Resolver

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
