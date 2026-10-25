defmodule HologramFeatureTests.Policies.Page6 do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.AccessDeniedError
  alias HologramFeatureTests.Components.Policies.Component7
  alias HologramFeatureTests.Entities.Leg
  alias HologramFeatureTests.Entities.Stop
  alias HologramFeatureTests.Entities.User

  route "/policies/6"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, "none")
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={command: :add_leg_to_archived_stop}> Add leg to archived stop </button>
      <button $click={command: :add_leg_to_own_stop}> Add leg to own stop </button>
      <button $click={command: :log_in}> Log in </button>
      <button $click={command: :rename_archived_leg}> Rename archived leg </button>
      <button $click={command: :rename_other_leg}> Rename other leg </button>
      <button $click={command: :rename_own_leg}> Rename own leg </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    <Component7 cid="component_7" />
    """
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:add_leg_to_archived_stop, _params, server) do
    add_leg("archived_stop", server)
  end

  def command(:add_leg_to_own_stop, _params, server) do
    add_leg("own_stop", server)
  end

  def command(:log_in, _params, server) do
    user =
      %{email: "session@example.com"}
      |> User.new()
      |> trust()
      |> DB.create!()

    put_action(%{server | user_id: user.id}, :show_result, result: "logged_in")
  end

  def command(:rename_archived_leg, _params, server) do
    rename_leg("archived_leg", server)
  end

  def command(:rename_other_leg, _params, server) do
    rename_leg("other_leg", server)
  end

  def command(:rename_own_leg, _params, server) do
    rename_leg("own_leg", server)
  end

  # Created on the acting user's authority, so the write asks the leg's create rule, which asks
  # whether the trip two rows away may be updated.
  defp add_leg(stop_name, server) do
    [stop] =
      Stop
      |> filter(name: ^stop_name)
      |> DB.read()

    result =
      try do
        %{name: "#{stop_name}_leg", stop_id: stop.id}
        |> Leg.new()
        |> DB.create!()

        "added_leg_to_#{stop_name}"
      rescue
        AccessDeniedError -> "refused_leg_on_#{stop_name}"
      end

    put_action(server, :show_result, result: result)
  end

  # Updated on the acting user's authority under the leg's rename rule, which wants an editor of
  # the trip two rows away while that trip is not archived.
  defp rename_leg(leg_name, server) do
    [leg] =
      Leg
      |> filter(name: ^leg_name)
      |> DB.read()

    result =
      try do
        leg
        |> put_attribute(:name, "#{leg_name}_renamed")
        |> authorize(:rename)
        |> DB.update!()

        "renamed_#{leg_name}"
      rescue
        AccessDeniedError -> "refused_rename_of_#{leg_name}"
      end

    put_action(server, :show_result, result: result)
  end
end
