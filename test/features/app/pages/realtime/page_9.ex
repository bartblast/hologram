defmodule HologramFeatureTests.Realtime.Page9 do
  use Hologram.Page

  route "/realtime/9"

  layout HologramFeatureTests.Components.DefaultLayout

  @channel_1 {:room, 1}
  @user_id 1

  def init(_params, component, server) do
    {
      put_state(component, :received, "none"),
      server
      |> log_in()
      |> put_subscription(@channel_1)
    }
  end

  def template do
    ~HOLO"""
    <p>Received: <strong id="received">{@received}</strong></p>
    <button $click={command: :log_out}>Log out</button>
    """
  end

  def action(:show, params, component) do
    put_state(component, :received, params[:message])
  end

  # Setting server.user_id to nil is what the framework diffs to announce the
  # identity change, which drives the in-place binding drop under test.
  def command(:log_out, _params, server) do
    Map.put(server, :user_id, nil)
  end

  # The feature-test app ships no auth UI, so a user is logged in inline.
  defp log_in(server) do
    Map.put(server, :user_id, @user_id)
  end
end
