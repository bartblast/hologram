defmodule HologramFeatureTests.Queries.Page13 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.Queries.Component20
  alias HologramFeatureTests.Entities.Channel
  alias HologramFeatureTests.Entities.Message

  route "/queries/13"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :local_answer, nil)
  end

  def template do
    ~HOLO"""
    <Component20 cid="component_20" />
    <p>
      <button $click="read_derived_fields_locally">Read derived fields locally</button>
    </p>
    {%if @local_answer}
      <p>
        Local answer: <strong id="local_answer"><code>{@local_answer}</code></strong>
      </p>
    {/if}
    """
  end

  # The read runs in the browser over the rows the component's queries synced, with bounds no
  # rendered list uses - so the answer can only come from the local rows.
  def action(:read_derived_fields_locally, _params, component) do
    channels =
      Channel
      |> filter(message_count > 1)
      |> include(recent_messages)
      |> DB.read()
      |> Enum.map_join(";", fn channel ->
        "#{channel.name}=#{Enum.map_join(channel.recent_messages, "/", & &1.body)}"
      end)

    summaries =
      Message
      |> filter(later_count > 0)
      |> sort(position)
      |> include(summary)
      |> DB.read()
      |> Enum.map_join(",", & &1.summary)

    put_state(component, :local_answer, "#{channels}|#{summaries}")
  end
end
