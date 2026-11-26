# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module190 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Template.Renderer.Module191

  state :row, :any

  @impl Component
  def init(_props, component, _server) do
    put_state(component, :row, Module15.new(%{token: "tok_parent_secret"}))
  end

  @impl Component
  def template do
    ~HOLO"""
    <Module191 cid="child" row={@row} />
    """
  end
end
