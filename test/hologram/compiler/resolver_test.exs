defmodule Hologram.Compiler.ResolverTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.Alias
  alias Hologram.Compiler.Resolver

  @aliases [
    %Alias{module: [:Abc, :Bcd], as: [:Bcd]},
    %Alias{module: [:Bcd, :Cde], as: [:Cde]}
  ]

  test "alias found" do
    result = Resolver.resolve([:Cde], @aliases)
    assert result == [:Bcd, :Cde]
  end

  test "alias not found" do
    result = Resolver.resolve([:Xyz], @aliases)
    assert result == [:Xyz]
  end
end
