# A struct with the two reflection functions of an Ecto schema, written by hand: the compiler treats
# a module that exports __changeset__/0 and __schema__/1 as an Ecto schema, and the feature test app
# does not depend on Ecto.
defmodule HologramFeatureTests.ReflectionFixture do
  defstruct name: "default"

  def __changeset__, do: %{name: :string}

  def __schema__(:fields), do: [:name]
end
