defmodule Hologram.Test.Fixtures.Template.Renderer.Module121 do
  use Hologram.Component

  state :password, :string, default: "hunter2", secret: true

  @impl Component
  def init(_props, component, _server) do
    put_state(component, :password, step(component.state))
  end

  @impl Component
  def template do
    ~HOLO""
  end

  defp step(%{step: step}), do: step
end
