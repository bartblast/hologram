defmodule HologramFeatureTests.SyncedTypesPage do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.UI.Link
  alias HologramFeatureTests.Entities.Bookmark
  alias HologramFeatureTests.SyncedTypesCountPage

  route "/synced-types"

  layout HologramFeatureTests.Components.DefaultLayout

  state :result, :string

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  # The page a stream connects on, and the way to a page reached after it. The bookmark is read in
  # the BROWSER, from the client's own database, and nothing on any page queries bookmarks.
  def template do
    ~HOLO"""
    <p>
      <button $click={action: :read_bookmark}> Read the bookmark </button>
      <Link to={SyncedTypesCountPage}>Count link</Link>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:read_bookmark, _params, component) do
    bookmark =
      Bookmark
      |> filter(label: "pinned")
      |> one()
      |> DB.read()

    result = if bookmark, do: "found_#{bookmark.label}", else: "missing"

    put_state(component, :result, result)
  end
end
