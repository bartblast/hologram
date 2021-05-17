defmodule Hologram.Compiler.ResolverTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.AST.Alias
  alias Hologram.Compiler.Resolver

  @aliases [
    %Alias{module: [:Abc, :Bcd], as: [:Bcd]},
    %Alias{module: [:Bcd, :Cde], as: [:Cde]}
  ]

  test "resolved" do
    result = Resolver.resolve([:Cde], @aliases)
    assert result == [:Bcd, :Cde]
  end

  test "not resolved" do
    result = Resolver.resolve([:Xyz], @aliases)
    refute result
  end
end
