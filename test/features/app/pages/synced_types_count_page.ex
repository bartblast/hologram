defmodule HologramFeatureTests.SyncedTypesCountPage do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.SyncedTypes.TodoCount
  alias HologramFeatureTests.Entities.Todo

  route "/synced-types-count"

  layout HologramFeatureTests.Components.DefaultLayout

  # Reached by a link from the page a stream connects on, so the count here is on a page the stream
  # was not greeted with. The todo is written in the BROWSER, and shows in the count only once the
  # count is answered from the client's own rows.
  def template do
    ~HOLO"""
    <p>
      <button $click={action: :add_todo}> Add a todo </button>
    </p>
    <TodoCount cid="todo_count" />
    """
  end

  def action(:add_todo, _params, component) do
    %{title: "added"}
    |> Todo.new()
    |> DB.create!()

    component
  end
end
