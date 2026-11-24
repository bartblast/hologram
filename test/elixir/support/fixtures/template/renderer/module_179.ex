# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module179 do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyEntity
  alias Hologram.Test.Fixtures.Template.Renderer.Module157
  alias Hologram.Test.Fixtures.Template.Renderer.Module180

  route "/hologram-test-fixtures-template-renderer-module179"

  layout Hologram.Test.Fixtures.Template.Renderer.Module49

  state :change_each_time, :boolean
  state :user_id, :string

  derived :page_entities, [PolicyEntity], fn -> sort(PolicyEntity, priority) end

  @impl Page
  def init(params, component, _server) do
    component
    |> put_state(:user_id, params.user_id)
    |> put_state(:change_each_time, Map.get(params, :change_each_time, false))
  end

  @impl Page
  def template do
    ~HOLO"""
    page = {Enum.map_join(@page_entities, ",", &Integer.to_string(&1.priority))};
    <Module157 />
    <Module180 cid="signing_in" user_id={@user_id} change_each_time={@change_each_time} />
    """
  end
end
