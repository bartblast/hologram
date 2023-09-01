defmodule Hologram.Test.Fixtures.Template.Renderer.Module36 do
  use Hologram.Component

  prop :a

  @impl Component
  def init(props, client, _server) do
    client
    |> put_state(props)
    |> put_state(z: "36z_state")
  end

  @impl Component
  def template do
    ~H"""
    {@a},<slot />{@z},
    """
  end
end
