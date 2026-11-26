# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module181 do
  use Hologram.Component

  alias Hologram.UI.Runtime

  prop :user_id, :string

  @impl Component
  def init(props, component, server) do
    {component, put_user_id(server, props.user_id)}
  end

  @impl Component
  def template do
    ~HOLO"""
    <Runtime />
    <slot />
    """
  end
end
