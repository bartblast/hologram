defmodule HologramFeatureTests.SequencePage do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Entities.Notice

  route "/sequence"

  layout HologramFeatureTests.Components.DefaultLayout

  state :marker, :integer
  state :view, :string

  # The server renders the view too, so the page carries the notices as its render read them.
  def init(_params, component, _server) do
    component
    |> put_state(:marker, 0)
    |> put_state(:view, view(0))
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="write_mine"> Write mine </button>
      <button $click="mark_read"> Mark read </button>
      <button $click="show_view"> Show view </button>
    </p>
    <p>
      View: <strong id="view"><code>{@view}</code></strong>
    </p>
    """
  end

  # Runs in the BROWSER, so the row waits in the write queue until the server takes it.
  def action(:write_mine, _params, component) do
    %{title: "mine"}
    |> Notice.new()
    |> DB.create!()

    component
  end

  # Moves the read marker to the newest final number, the way an app marks a channel read.
  def action(:mark_read, _params, component) do
    case newest() do
      nil -> component
      notice -> put_state(component, :marker, notice.server_created_seq)
    end
  end

  def action(:show_view, _params, component) do
    put_state(component, :view, view(component.state.marker))
  end

  # Four reads: the notices by their created number, ascending and descending, the newest one with
  # a final number, and the ones created after the read marker.
  defp view(marker) do
    ascending =
      Notice
      |> sort(server_created_seq)
      |> DB.read()

    descending =
      Notice
      |> sort(server_created_seq: :desc)
      |> DB.read()

    unread =
      Notice
      |> filter(server_created_seq > ^marker)
      |> sort(server_created_seq)
      |> DB.read()

    newest_title =
      case newest() do
        nil -> "none"
        notice -> notice.title
      end

    "#{titles(ascending)} | #{titles(descending)} | #{newest_title} | #{titles(unread)}"
  end

  defp newest do
    Notice
    |> filter(server_created_seq != nil)
    |> sort(server_created_seq: :desc)
    |> take(1)
    |> one()
    |> DB.read()
  end

  defp titles([]), do: "none"

  defp titles(notices), do: Enum.map_join(notices, ", ", & &1.title)
end
