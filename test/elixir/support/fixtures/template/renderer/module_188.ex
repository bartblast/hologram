# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module188 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Template.Renderer.Module189

  @impl Component
  def init(_props, component, _server) do
    put_context(component, {:module_188, :row}, Module15.new(%{token: "tok_context_secret"}))
  end

  @impl Component
  def template do
    ~HOLO"""
    <Module189 />
    """
  end
end
