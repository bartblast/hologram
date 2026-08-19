# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module103 do
  use Hologram.Page

  alias Hologram.Auth
  alias Hologram.Test.Fixtures.Policy.Module1

  param :entity_id, :string

  route "/hologram-test-fixtures-template-renderer-module103/:entity_id"

  # The layout that renders Hologram.UI.Runtime, which is what puts the mount data - the rows a
  # page carries among it - into the page.
  layout Hologram.Test.Fixtures.Template.Renderer.Module49

  @impl Page
  def init(params, component, server) do
    put_state(component, entity: %Module1{id: params.entity_id}, user_id: server.user_id)
  end

  # Checked while RENDERING, so the client re-runs the same check - and needs the row answering
  # it before the fill arrives.
  @impl Page
  def template do
    ~HOLO"""
    may read = {Auth.can?(@user_id, :read, @entity)}
    """
  end
end
