# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module34 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Template.Renderer.Module35
  alias Hologram.Test.Fixtures.Template.Renderer.Module36

  prop :a, :string

  def init(props, component, _server) do
    component
    |> put_state(props)
    |> put_state(b: "34b_state", c: "34c_state", x: "34x_state", y: "34y_state", z: "34z_state")
  end

  @impl Component
  def template do
    ~HOLO"""
    {@a},<Module35 cid="component_35" a="35a_prop">{@b},<Module36 cid="component_36" a="36a_prop">{@c},<slot />,{@x},</Module36>{@y},</Module35>{@z}
    """
  end
end
