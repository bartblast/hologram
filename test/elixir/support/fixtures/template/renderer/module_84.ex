defmodule Hologram.Test.Fixtures.Template.Renderer.Module84 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.Renderer.Module82

  route "/hologram-test-fixtures-template-renderer-module84"

  layout Hologram.Test.Fixtures.Template.Renderer.Module85

  @impl Page
  def init(_params, component, server) do
    {component,
     put_broadcast(server, {:instance, server.instance_id}, :page_broadcast, level: "page")}
  end

  @impl Page
  def template do
    ~HOLO"""
    <Module82 cid="comp_1" />
    <Module82 cid="comp_2" />
    """
  end
end
