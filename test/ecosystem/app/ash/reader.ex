# Reads one field of a record through an interface function, for the test that the field's value
# holds only that field's types: the record's money field must not reach it.
defmodule HologramEcosystemTests.Ash.Reader do
  alias HologramEcosystemTests.Ash.Item

  def title(id), do: Item.get!(id).title

  def stamp_by_interface(id), do: Item.get!(id).stamp

  def stamp_by_api(id), do: Ash.get!(Item, id).stamp
end
