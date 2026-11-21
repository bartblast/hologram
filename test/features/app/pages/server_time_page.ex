defmodule HologramFeatureTests.ServerTimePage do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Entities.Notice

  route "/server-time"

  layout HologramFeatureTests.Components.DefaultLayout

  state :order, :string

  def init(_params, component, _server) do
    put_state(component, :order, "unread")
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="write_mine"> Write mine </button>
      <button $click="show_order"> Show order </button>
    </p>
    <p>
      Order: <strong id="order"><code>{@order}</code></strong>
    </p>
    """
  end

  # The write runs in the BROWSER, so the row it makes carries this browser's clock in created_at
  # and nothing in server_created_at until the server's own row arrives.
  def action(:write_mine, _params, component) do
    %{title: "mine"}
    |> Notice.new()
    |> DB.create!()

    component
  end

  # Three reads of the browser's own database: the notices by their writer's time, by the server's,
  # and the ones the server has not stamped yet.
  def action(:show_order, _params, component) do
    by_writer =
      Notice
      |> sort(created_at)
      |> DB.read()

    by_server =
      Notice
      |> sort(server_created_at)
      |> DB.read()

    unstamped =
      Notice
      |> filter(server_created_at == nil)
      |> DB.read()

    put_state(
      component,
      :order,
      "#{titles(by_writer)} | #{titles(by_server)} | #{titles(unstamped)}"
    )
  end

  defp titles([]), do: "none"

  defp titles(notices), do: Enum.map_join(notices, ", ", & &1.title)
end
