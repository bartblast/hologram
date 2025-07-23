defmodule HologramFeatureTests.Session.Page6 do
  use Hologram.Page

  route "/session/6"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, command_executed?: false)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={command: :delete_from_session}>Delete from session</button>
    </p>
    <p>
      command_executed? = {inspect(@command_executed?)}
    </p>
    """
  end

  def action(:set_command_executed_flag, _params, component) do
    put_state(component, :command_executed?, true)
  end

  def command(:delete_from_session, _params, server) do
    server
    |> delete_session("session_key")
    |> put_action(:set_command_executed_flag)
  end
end
