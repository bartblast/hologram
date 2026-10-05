# Puts an Ecto schema into state, and its action calls __changeset__/0 on the schema it reads from
# state, a module the client code does not name: the page's bundle must get that function.
defmodule HologramEcosystemTests.Ecto.OpenPage do
  use Hologram.Page

  alias HologramEcosystemTests.Ecto.Tag

  route "/ecto/open"

  layout HologramEcosystemTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, fields: "", schema: Tag)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="reflect"> Reflect </button>
    </p>
    <p>
      Fields: <strong id="fields">{@fields}</strong>
    </p>
    """
  end

  def action(:reflect, _params, component) do
    fields =
      component.state.schema.__changeset__()
      |> Map.keys()
      |> Enum.map(&Atom.to_string/1)
      |> Enum.sort()
      |> Enum.join(",")

    put_state(component, :fields, fields)
  end
end
