defmodule Hologram.Test.Fixtures.Template.Renderer.Module70 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Template.Renderer.Module72

  route "/hologram-test-fixtures-template-renderer-module70"

  layout Hologram.Test.Fixtures.Template.Renderer.Module71

  def init(_params, _component, server) do
    put_cookie(server, "cookie_key_page", :cookie_value_page)
  end

  @impl Page
  def template do
    ~HOLO"""
    <Module72 cid="component_72" />
    """
  end
end
