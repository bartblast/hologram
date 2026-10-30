defmodule HologramFeatureTests.Queries.Page4 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.Queries.Component11
  alias HologramFeatureTests.Components.Queries.Component12
  alias HologramFeatureTests.Entities.Ticket

  route "/queries/4"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :local_titles, nil)
  end

  def template do
    ~HOLO"""
    <Component11 cid="component_11" min_priority={:medium} page_size={2} skipped_title="delta" />
    <Component12 cid="component_12" page={2} size={2} sort_by={:title} />
    <p>
      <button $click="read_locally">Read locally</button>
    </p>
    {%if @local_titles}
      <p>
        Runtime filter: <strong id="runtime_filter"><code>{@local_titles}</code></strong>
      </p>
    {/if}
    """
  end

  # The conditions are data built at run time, the way a report builder would assemble them, and
  # the read runs in the browser over the rows the page's queries brought in.
  def action(:read_locally, _params, component) do
    predicates = [priority: {:>=, :medium}, title: {:!=, "delta"}]

    titles =
      Ticket
      |> filter(^predicates)
      |> sort(title)
      |> DB.read()
      |> Enum.map_join(",", & &1.title)

    put_state(component, :local_titles, titles)
  end
end
