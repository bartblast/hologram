# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Rules3 do
  @behaviour Hologram.Compiler.DataFlow.Rules

  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct2

  @impl Hologram.Compiler.DataFlow.Rules
  def summary(_mfa, _flow), do: nil

  @impl Hologram.Compiler.DataFlow.Rules
  def record(Struct1, _flow), do: [{:struct, Struct1, %{field: [:prim]}}]

  def record(Struct2, _flow), do: [{:struct, Struct2, %{}}]

  def record(_module, _flow), do: nil

  @impl Hologram.Compiler.DataFlow.Rules
  def resolve(_part, _modules, _flow), do: raise("not used")
end
