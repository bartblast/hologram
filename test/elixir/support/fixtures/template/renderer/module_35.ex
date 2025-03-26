# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module35 do
  use Hologram.Component

  prop :a, :string

  def init(props, component, _server) do
    component
    |> put_state(props)
    |> put_state(z: "35z_state")
  end

  @impl Component
  def template do
    ~HOLO"""
    {@a},<slot />{@z},
    """
  end
end
