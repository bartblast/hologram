defmodule HologramFeatureTests.Session.Page2 do
  use Hologram.Page

  route "/session/2"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, server) do
    put_state(component, :value, get_session(server, "session_key"))
  end

  def template do
    ~HOLO"value = {inspect(@value)}"
  end
end
