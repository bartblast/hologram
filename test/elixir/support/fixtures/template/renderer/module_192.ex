# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module192 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module15

  prop :id, :string

  state :init_token, :any

  derived :derived_token, :string, fn id -> inspect(DB.read(Module15, id).token) end

  @impl Component
  def init(props, component, _server) do
    put_state(component, :init_token, DB.read(Module15, props.id).token)
  end

  @impl Component
  def template do
    ~HOLO"""
    template = {inspect(DB.read(Module15, @id).token)}; derived = {@derived_token}
    """
  end
end
