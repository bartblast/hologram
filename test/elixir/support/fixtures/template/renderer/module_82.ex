# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module82 do
  use Hologram.Component

  def init(_props, component, server) do
    {component,
     put_broadcast(server, {:instance, server.instance_id}, :component_broadcast, text: "hi")}
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
