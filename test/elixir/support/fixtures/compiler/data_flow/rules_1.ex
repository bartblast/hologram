# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Rules1 do
  @behaviour Hologram.Compiler.DataFlow.Rules

  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module25
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  @impl Hologram.Compiler.DataFlow.Rules
  def summary({Module25, :ruled, 0}, _flow), do: [{:struct, Struct1, %{field: [:prim]}}]

  def summary(_mfa, _flow), do: nil

  @impl Hologram.Compiler.DataFlow.Rules
  def resolve(_part, _modules, _flow), do: raise("not used")
end
