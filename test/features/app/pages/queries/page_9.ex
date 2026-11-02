defmodule HologramFeatureTests.Queries.Page9 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.Queries.Component17
  alias HologramFeatureTests.Entities.Channel

  route "/queries/9"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    component
    |> put_state(:body, "bye")
    |> put_state(:local_names, nil)
  end

  def template do
    ~HOLO"""
    <Component17 cid="component_17" />
    <p>
      <button $click="read_channels_with_a_bye_locally">Read channels with a bye locally</button>
    </p>
    {%if @local_names}
      <p>
        Local channels with a bye: <strong id="local_bye_channels"><code>{@local_names}</code></strong>
      </p>
    {/if}
    """
  end

  # The read runs in the browser and answers random, a channel no rendered list holds, so the page
  # never carried it - the answer can only come from rows the stream filled in.
  def action(:read_channels_with_a_bye_locally, _params, component) do
    body = component.state.body

    names =
      Channel
      |> filter(any(message <- messages, message.body == ^body))
      |> sort(name)
      |> DB.read()
      |> Enum.map_join(",", & &1.name)

    put_state(component, :local_names, names)
  end
end
