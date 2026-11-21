defmodule HologramFeatureTests.QuerySnapshotPage do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.UI.Link
  alias HologramFeatureTests.BigIntegersPage
  alias HologramFeatureTests.Entities.Todo

  route "/query-snapshot"

  layout HologramFeatureTests.Components.DefaultLayout

  state :query, :any
  state :result, :string

  def init(_params, component, _server) do
    component
    |> put_state(:query, nil)
    |> put_state(:result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={action: :hold_query}> Hold query </button>
      <button $click={action: :read_query}> Read query </button>
      <Link to={BigIntegersPage}>Leave the page</Link>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:hold_query, _params, component) do
    component
    |> put_state(:query, filter(Todo, done: true))
    |> put_state(:result, "held")
  end

  def action(:read_query, _params, component) do
    titles =
      component.state.query
      |> DB.read()
      |> Enum.map_join(",", & &1.title)

    put_state(component, :result, "read_[#{titles}]")
  end
end
