# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module35 do
  use Hologram.Component

  prop :a, :string

  def init(props, component, server) do
    new_component =
      component
      |> put_state(props)
      |> put_state(z: "35z_state")

    new_server = put_cookie(server, "cookie_key_35", :cookie_value_35)

    {new_component, new_server}
  end

  @impl Component
  def template do
    ~HOLO"""
    {@a},<slot />{@z},
    """
  end
end
