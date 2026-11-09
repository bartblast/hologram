defmodule Hologram.Test.Fixtures.Template.Renderer.Module81 do
  use Hologram.Component

  state :observed_cid, :string

  @impl Component
  def init(_props, component, server) do
    put_state(component, observed_cid: server.cid)
  end

  @impl Component
  def template do
    ~HOLO"<slot />"
  end
end
