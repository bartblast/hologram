# credo:disable-for-this-file Credo.Check.Refactor.Apply
defmodule Hologram.Test.Fixtures.Template.Renderer.Module126 do
  use Hologram.Component

  state :password, :string, default: "hunter2", secret: true

  @impl Component
  def init(_props, component, _server) do
    target = Map.get(component.state, :target, component.state)
    put_state(component, :password, apply(target, :foo, []))
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
