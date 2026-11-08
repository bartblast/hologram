# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module36 do
  use Hologram.Component

  prop :a, :string

  state :z, :string

  def init(_props, component, server) do
    new_component =
      put_state(component, z: "36z_state")

    new_server = put_cookie(server, "cookie_key_36", :cookie_value_36)

    {new_component, new_server}
  end

  @impl Component
  def template do
    ~HOLO"""
    {@a},<slot />{@z},
    """
  end
end
