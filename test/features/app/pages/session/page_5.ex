defmodule HologramFeatureTests.Session.Page5 do
  use Hologram.Page

  route "/session/5"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, command_executed?: false, session_value: nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={command: :read_from_session}>Read from session</button>
    </p>
    <p>
      command_executed? = {inspect(@command_executed?)}, session_value = {inspect(@session_value)}
    </p>
    """
  end

  def action(:update_state_with_session_value, params, component) do
    put_state(component, command_executed?: true, session_value: params.session_value)
  end

  def command(:read_from_session, _params, server) do
    session_value = get_session(server, "session_key")

    put_action(server, :update_state_with_session_value, session_value: session_value)
  end
end
