defmodule Hologram.Test.Fixtures.Template.Renderer.Module116 do
  use Hologram.Component

  state :count, :integer, default: 5
  state :password, :string, default: "", secret: true

  @impl Component
  def init(_props, component, _server) do
    put_state(component, :password, "hunter2")
  end

  @impl Component
  def template do
    ~HOLO"<p>{@missing}</p>"
  end
end
