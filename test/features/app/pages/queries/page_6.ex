defmodule HologramFeatureTests.Queries.Page6 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.Queries.Component14
  alias HologramFeatureTests.Entities.Booking

  route "/queries/6"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :local_names, nil)
  end

  def template do
    ~HOLO"""
    <Component14 cid="component_14" />
    <p>
      <button $click="read_overbooked_locally">Read overbooked locally</button>
    </p>
    {%if @local_names}
      <p>
        Local overbooked: <strong id="local_overbooked"><code>{@local_names}</code></strong>
      </p>
    {/if}
    """
  end

  # The read runs in the browser over the rows the component's queries synced, comparing two
  # attributes the rendered lists never compare - so the answer can only come from the local rows.
  def action(:read_overbooked_locally, _params, component) do
    names =
      Booking
      |> filter(guests >= capacity)
      |> sort(name)
      |> DB.read()
      |> Enum.map_join(",", & &1.name)

    put_state(component, :local_names, names)
  end
end
