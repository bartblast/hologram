defmodule HologramFeatureTests.Session.Page4 do
  use Hologram.Page

  route "/session/4"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, command_executed?: false)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={command: :write_to_session}>Write to session</button>
    </p>
    <p>
      command_executed? = {inspect(@command_executed?)}
    </p>
    """
  end

  def action(:set_command_executed_flag, _params, component) do
    put_state(component, :command_executed?, true)
  end

  def command(:write_to_session, _params, server) do
    server
    |> put_session("session_key", :abc)
    |> put_action(:set_command_executed_flag)
  end
end
