# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module85 do
  use Hologram.Component

  def init(_props, component, server) do
    {component,
     put_broadcast(server, {:instance, server.instance_id}, :layout_broadcast, level: "layout")}
  end

  @impl Component
  def template do
    ~HOLO"<slot />"
  end
end
