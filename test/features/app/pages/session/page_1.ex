defmodule HologramFeatureTests.Session.Page1 do
  use Hologram.Page

  route "/session/1"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, _component, server) do
    put_session(server, "session_key", :abc)
  end

  def template do
    ~HOLO""
  end
end
