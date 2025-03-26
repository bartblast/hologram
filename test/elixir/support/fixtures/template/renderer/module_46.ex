defmodule Hologram.Test.Fixtures.Template.Renderer.Module46 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module46"

  layout Hologram.Test.Fixtures.Template.Renderer.Module47

  @impl Page
  def init(_params, component, _server) do
    put_context(component, {:my_scope, :my_key}, 123)
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
