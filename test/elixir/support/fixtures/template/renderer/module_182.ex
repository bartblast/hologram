# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module182 do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyEntity
  alias Hologram.Test.Fixtures.Template.Renderer.Module157

  route "/hologram-test-fixtures-template-renderer-module182"

  layout Hologram.Test.Fixtures.Template.Renderer.Module181

  state :user_id, :string

  derived :page_entities, [PolicyEntity], fn -> sort(PolicyEntity, priority) end

  @impl Page
  def init(params, component, _server) do
    put_state(component, :user_id, params.user_id)
  end

  @impl Page
  def template do
    ~HOLO"""
    page = {Enum.map_join(@page_entities, ",", &Integer.to_string(&1.priority))};
    <Module157 />
    """
  end
end
