defmodule Hologram.Test.Fixtures.Template.Renderer.Module103 do
  use Hologram.Component

  state :a, :integer, default: 1

  @impl Component
  def init(_props, _component, server) do
    put_cookie(server, "cookie_key_103", :cookie_value_103)
  end

  @impl Component
  def template do
    ~HOLO"<div>state_a = {@a}</div>"
  end
end
