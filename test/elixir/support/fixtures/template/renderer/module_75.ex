defmodule Hologram.Test.Fixtures.Template.Renderer.Module75 do
  use Hologram.Component

  def init(_props, _component, server) do
    put_cookie(server, "cookie_key_75", :cookie_value_75)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
