defmodule Hologram.Test.Fixtures.Template.Renderer.Module154 do
  use Hologram.Component

  state :suffix, :string, default: "?"

  derived :shout, :string, fn suffix -> "Hi" <> suffix end

  @impl Component
  def init(_props, component, _server) do
    put_state(component, :suffix, "!")
  end

  @impl Component
  def template do
    ~HOLO"shout = {@shout}"
  end
end
