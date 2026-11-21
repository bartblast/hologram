defmodule HologramFeatureTests.Policies.Page13 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.Policies.Component14
  alias HologramFeatureTests.Entities.Locker
  alias HologramFeatureTests.Entities.Slip

  route "/policies/13"

  layout HologramFeatureTests.Components.DefaultLayout

  state :locker_id, :any
  state :new_slip, :string

  def template do
    ~HOLO"""
    <p>
      <button $click="check_new_slip"> Check new slip </button>
      <button $click="create_locker"> Create locker </button>
      <button $click="create_slips"> Create slips </button>
    </p>
    <p>
      New slip: <strong id="new_slip"><code>{@new_slip}</code></strong>
    </p>
    <Component14 cid="component_14" />
    """
  end

  def init(_params, component, _server) do
    component
    |> put_state(:locker_id, nil)
    |> put_state(:new_slip, "none")
  end

  # Each action runs in the browser, so the rows it creates show at once, before the server has
  # judged whether the user may read them.
  def action(:check_new_slip, _params, component) do
    slip = Slip.new(%{label: "new", locker_id: component.state.locker_id})

    result = if can?(nil, :read, slip), do: "true", else: "false"

    put_state(component, :new_slip, result)
  end

  def action(:create_locker, _params, component) do
    {:ok, locker} =
      %{open: true}
      |> Locker.new()
      |> DB.create()

    {:ok, _slip} =
      %{label: "boxed", locker_id: locker.id}
      |> Slip.new()
      |> DB.create()

    put_state(component, :locker_id, locker.id)
  end

  def action(:create_slips, _params, component) do
    {:ok, _shared} =
      %{label: "shared", shared: true}
      |> Slip.new()
      |> DB.create()

    {:ok, _orphan} =
      %{label: "orphan"}
      |> Slip.new()
      |> DB.create()

    component
  end
end
