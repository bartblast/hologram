# credo:disable-for-this-file Credo.Check.Readability.Specs
# Shaped like an Ecto embedded schema with one field, without Ecto: the compiler knows a schema by its
# __schema__/1,2 and __changeset__/0 (see Hologram.Reflection.ecto_schema?/1), which is all these
# tests need. Real Ecto schemas are tested in the ecosystem tests app (test/ecosystem).
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module35 do
  defstruct id: nil, my_field: nil

  def __changeset__, do: %{id: :binary_id, my_field: :string}

  def __schema__(:fields), do: [:id, :my_field]

  def __schema__(_query), do: nil

  def __schema__(:type, field), do: Map.get(__changeset__(), field)

  def __schema__(_query, _field), do: nil
end
