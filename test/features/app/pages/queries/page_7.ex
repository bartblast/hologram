defmodule HologramFeatureTests.Queries.Page7 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.Queries.Component15
  alias HologramFeatureTests.Entities.Stop

  route "/queries/7"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    component
    |> put_state(:local_names, nil)
    |> put_state(:trip_name, "alpha")
  end

  def template do
    ~HOLO"""
    <Component15 cid="component_15" />
    <p>
      <button $click="read_alpha_stops_locally">Read alpha stops locally</button>
    </p>
    {%if @local_names}
      <p>
        Local alpha stops: <strong id="local_alpha_stops"><code>{@local_names}</code></strong>
      </p>
    {/if}
    """
  end

  # The read runs in the browser over the stops the component's query synced and the trips its
  # window downloaded along the path, comparing the trip's name with a value the rendered list
  # never compares - so the answer can only come from the local rows.
  def action(:read_alpha_stops_locally, _params, component) do
    trip_name = component.state.trip_name

    names =
      Stop
      |> filter(trip.name == ^trip_name)
      |> order_by(name)
      |> DB.read()
      |> Enum.map_join(",", & &1.name)

    put_state(component, :local_names, names)
  end
end
