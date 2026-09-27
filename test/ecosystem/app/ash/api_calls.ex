# Calls Ash's own functions the way app code does, for the tests of what the data flow rules answer
# for them.
defmodule HologramEcosystemTests.Ash.ApiCalls do
  require Ash.Query

  alias HologramEcosystemTests.Ash.Item
  alias HologramEcosystemTests.Ash.Note

  def counted, do: Ash.count!(Item)

  def created do
    Item
    |> Ash.Changeset.for_create(:create, %{title: "text"})
    |> Ash.create!()
  end

  def fetched(id), do: Ash.get(Item, id)

  def filtered do
    Item
    |> Ash.Query.filter(title == "text")
    |> Ash.read!()
  end

  def loaded(id) do
    Item
    |> Ash.get!(id)
    |> Ash.load!(:notes)
  end

  def updated(item), do: Ash.update!(item, %{title: "text"})

  def updates_fetched(id), do: updated(Ash.get!(Item, id))

  def with_actor, do: Ash.read!(Item, actor: %Note{})
end
