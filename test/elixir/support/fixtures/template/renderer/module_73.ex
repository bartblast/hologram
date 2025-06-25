defmodule Hologram.Test.Fixtures.Template.Renderer.Module73 do
  use Hologram.Component

  @impl Component
  def init(_props, _component, server) do
    put_cookie(server, "cookie_key_73", :cookie_value_73)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
