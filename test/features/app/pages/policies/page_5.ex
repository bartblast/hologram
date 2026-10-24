defmodule HologramFeatureTests.Policies.Page5 do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.AccessDeniedError
  alias HologramFeatureTests.Components.Policies.Component6
  alias HologramFeatureTests.Entities.Stop
  alias HologramFeatureTests.Entities.Trip
  alias HologramFeatureTests.Entities.User

  route "/policies/5"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, "none")
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={command: :add_stop_to_archived_trip}> Add stop to archived trip </button>
      <button $click={command: :add_stop_to_other_trip}> Add stop to other trip </button>
      <button $click={command: :add_stop_to_own_trip}> Add stop to own trip </button>
      <button $click={command: :log_in}> Log in </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    <Component6 cid="component_6" />
    """
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:add_stop_to_archived_trip, _params, server) do
    add_stop("archived_trip", server)
  end

  def command(:add_stop_to_other_trip, _params, server) do
    add_stop("other_trip", server)
  end

  def command(:add_stop_to_own_trip, _params, server) do
    add_stop("own_trip", server)
  end

  def command(:log_in, _params, server) do
    user =
      %{email: "session@example.com"}
      |> User.new()
      |> trust()
      |> DB.create!()

    put_action(%{server | user_id: user.id}, :show_result, result: "logged_in")
  end

  # Created on the acting user's authority, so the write asks the stop's create rule, which asks
  # whether the trip may be updated.
  defp add_stop(trip_name, server) do
    [trip] =
      Trip
      |> filter(name: ^trip_name)
      |> DB.read()

    result =
      try do
        %{name: "#{trip_name}_stop", trip_id: trip.id}
        |> Stop.new()
        |> DB.create!()

        "added_stop_to_#{trip_name}"
      rescue
        AccessDeniedError -> "refused_stop_on_#{trip_name}"
      end

    put_action(server, :show_result, result: result)
  end
end
