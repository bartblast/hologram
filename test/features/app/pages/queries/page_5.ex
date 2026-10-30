defmodule HologramFeatureTests.Queries.Page5 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.Queries.Component13
  alias HologramFeatureTests.Entities.Ticket

  route "/queries/5"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :local_titles, nil)
  end

  def template do
    ~HOLO"""
    <Component13 cid="component_13" skipped_title="delta" />
    <p>
      <button $click="read_alternatives_locally">Read alternatives locally</button>
    </p>
    {%if @local_titles}
      <p>
        Local alternatives: <strong id="local_alternatives"><code>{@local_titles}</code></strong>
      </p>
    {/if}
    """
  end

  # The read runs in the browser over the rows the app's queries synced - delta is among them
  # although the rendered list skips it, which is what proves the read answered from the local
  # rows rather than from the rendered result.
  def action(:read_alternatives_locally, _params, component) do
    titles =
      Ticket
      |> filter(title == "alpha" or (priority == :high and title != "zz"))
      |> sort(title)
      |> DB.read()
      |> Enum.map_join(",", & &1.title)

    put_state(component, :local_titles, titles)
  end
end
