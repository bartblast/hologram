defmodule HologramFeatureTests.StoppedTabPage do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.UI.Link
  alias HologramFeatureTests.Components.ActionWrites.Todos
  alias HologramFeatureTests.Entities.Todo
  alias HologramFeatureTests.WriteQueuePage

  route "/stopped-tab"

  layout HologramFeatureTests.Components.DefaultLayout

  # What a tab the server stopped serving after a deploy does: it writes in the BROWSER and leaves
  # by a link or by an action naming the next page, and each of those is something the scenarios
  # ask about once the tab has been stopped.
  #
  # A button is clicked by a label the browser driver matches as a SUBSTRING, so no label here may
  # contain another's.
  def template do
    ~HOLO"""
    <p>
      <button $click={action: :create_alpha}> Create alpha </button>
      <button $click={action: :go_to_write_queue}> Go to the write queue </button>
      <Link to={WriteQueuePage}>Write queue link</Link>
    </p>
    <Todos cid="todos" />
    """
  end

  def action(:create_alpha, _params, component) do
    %{title: "alpha"}
    |> Todo.new()
    |> DB.create!()

    component
  end

  def action(:go_to_write_queue, _params, component) do
    put_page(component, WriteQueuePage)
  end
end
