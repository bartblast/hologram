# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Rules1 do
  @behaviour Hologram.Compiler.DataFlow.Rules

  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module25
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct2

  @impl Hologram.Compiler.DataFlow.Rules
  def summary({Module25, :loads, 1}, _flow), do: [{:rule, __MODULE__, :loaded, [[{:param, 0}]]}]

  def summary({Module25, :reads, 1}, _flow), do: [{:rule, __MODULE__, :read, [[{:param, 0}]]}]

  def summary({Module25, :reads_loaded, 1}, _flow),
    do: [{:rule, __MODULE__, :read_loaded, [[{:param, 0}]]}]

  def summary({Module25, :ruled, 0}, _flow), do: [{:struct, Struct1, %{field: [:prim]}}]

  def summary({Module25, :structs_of, 1}, _flow),
    do: [{:rule, __MODULE__, :structs, [[{:param, 0}]]}]

  def summary(_mfa, _flow), do: nil

  # A call of `built/0` on each module among the first argument's atoms.
  @impl Hologram.Compiler.DataFlow.Rules
  def resolve(:loaded, [atoms], _flow),
    do: for(atom <- atoms, do: {:dyn, [{:atom, atom}], :built, 0, []})

  # A struct with no fields for each struct module among the first argument's atoms; a Struct2 when
  # there is none, standing for a rules module's fallback (every record it knows).
  def resolve(:read, [atoms], flow) do
    case resolve(:structs, [atoms], flow) do
      [] -> [{:struct, Struct2, %{}}]
      structs -> structs
    end
  end

  # As `:read`, with a fallback holding a call (what `Module25.built/0` gives).
  def resolve(:read_loaded, [atoms], flow) do
    case resolve(:structs, [atoms], flow) do
      [] -> [{:dyn, [{:atom, Module25}], :built, 0, []}]
      structs -> structs
    end
  end

  # A struct with no fields for each struct module among the first argument's atoms.
  def resolve(:structs, [atoms], _flow) do
    for atom <- atoms, Code.ensure_loaded?(atom), function_exported?(atom, :__struct__, 0) do
      {:struct, atom, %{}}
    end
  end
end
