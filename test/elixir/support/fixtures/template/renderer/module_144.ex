defmodule Hologram.Test.Fixtures.Template.Renderer.Module144 do
  use Hologram.Component

  prop :first_name, :string

  state :seen, :string

  derived :greeting, :string, fn first_name -> "Hi " <> first_name end

  @impl Component
  def init(_props, component, _server) do
    put_state(component, :seen, component.derived.greeting)
  end

  @impl Component
  def template do
    ~HOLO"seen = {@seen}"
  end
end
