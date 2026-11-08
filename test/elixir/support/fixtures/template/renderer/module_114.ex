defmodule Hologram.Test.Fixtures.Template.Renderer.Module114 do
  use Hologram.Component

  state :count, :integer, default: 0
  state :password, :string, default: "", secret: true

  @impl Component
  def init(_props, _component, _server) do
    %Component{state: %{count: 1, password: "hunter2"}}
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
