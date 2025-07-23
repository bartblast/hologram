defmodule HologramFeatureTests.Session.Page3 do
  use Hologram.Page

  route "/session/3"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, _component, server) do
    delete_session(server, "session_key")
  end

  def template do
    ~HOLO""
  end
end
