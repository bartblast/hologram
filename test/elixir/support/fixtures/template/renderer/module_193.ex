# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module193 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module15

  prop :id, :string

  state :entity_id, :string

  # It reads state, so it's computed once init/3 has returned.
  derived :derived_token, :string, fn entity_id -> inspect(DB.read(Module15, entity_id).token) end

  @impl Component
  def init(props, component, _server) do
    put_state(component, :entity_id, props.id)
  end

  @impl Component
  def template do
    ~HOLO"derived = {@derived_token}"
  end
end
