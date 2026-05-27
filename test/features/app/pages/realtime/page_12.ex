defmodule HologramFeatureTests.Realtime.Page12 do
  use Hologram.Page

  route "/realtime/12/:user_id"

  param :user_id, :integer

  layout HologramFeatureTests.Components.DefaultLayout

  @channel_1 {:room, 1}

  # The feature-test app ships no auth UI, so the user from the route param is
  # logged in inline.
  def init(params, component, server) do
    {
      put_state(component, :received, "none"),
      server
      |> Map.put(:user_id, params.user_id)
      |> put_subscription(@channel_1)
    }
  end

  def template do
    ~HOLO"""
    <p>Received: <strong id="received">{@received}</strong></p>
    <button $click={command: :broadcast_except_user}>Exclude user</button>
    """
  end

  def action(:show, params, component) do
    put_state(component, :received, params[:message])
  end

  def command(:broadcast_except_user, _params, server) do
    put_broadcast_except(server, {:user, server.user_id}, @channel_1, :show,
      message: "delivered to all other users"
    )
  end
end
