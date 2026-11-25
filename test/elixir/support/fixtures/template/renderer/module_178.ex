# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module178 do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyEntity
  alias Hologram.Test.Fixtures.Template.Renderer.Module157

  route "/hologram-test-fixtures-template-renderer-module178"

  # The layout that renders Hologram.UI.Runtime, which is what puts the mount data into the page.
  layout Hologram.Test.Fixtures.Template.Renderer.Module49

  # These read no state, so they're computed before init/3.
  derived :page_entities, [PolicyEntity], fn -> sort(PolicyEntity, priority) end
  derived :page_total, :integer, fn -> count(PolicyEntity) end

  @impl Page
  def init(%{user_id: user_id}, component, server) do
    {component, put_user_id(server, user_id)}
  end

  @impl Page
  def template do
    ~HOLO"""
    page = {Enum.map_join(@page_entities, ",", &Integer.to_string(&1.priority))};
    total = {@page_total};
    <Module157 />
    """
  end
end
