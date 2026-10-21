defmodule HologramFeatureTests.Policies.Page3 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.Policies.Component4
  alias HologramFeatureTests.Entities.Booking

  route "/policies/3"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :local_names, nil)
  end

  def template do
    ~HOLO"""
    <Component4 cid="component_4" />
    <p>
      <button $click="check_unconfirmable_locally">Check unconfirmable locally</button>
    </p>
    {%if @local_names}
      <p>
        Local unconfirmable: <strong id="local_unconfirmable"><code>{@local_names}</code></strong>
      </p>
    {/if}
    """
  end

  # The read and the check both run in the browser, over the rows the component's query synced and
  # the rules the build carries - the complement of the rendered list, which no render shows.
  def action(:check_unconfirmable_locally, _params, component) do
    names =
      Booking
      |> order_by(name)
      |> DB.read()
      |> Enum.reject(&can?(nil, :confirm, &1))
      |> Enum.map_join(",", & &1.name)

    put_state(component, :local_names, names)
  end
end
