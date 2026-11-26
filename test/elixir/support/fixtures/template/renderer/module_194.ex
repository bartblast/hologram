# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module194 do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module15

  route "/hologram-test-fixtures-template-renderer-module194"

  param :id, :string
  param :user_id, :string

  # The layout that renders Hologram.UI.Runtime, which is what puts the mount data into the page.
  layout Hologram.Test.Fixtures.Template.Renderer.Module49

  # It reads no state, so it's computed before init/3, and again for the user init/3 signs in.
  derived :derived_token, :string, fn id -> inspect(DB.read(Module15, id).token) end

  @impl Page
  def init(%{user_id: user_id}, component, server) do
    {component, put_user_id(server, user_id)}
  end

  @impl Page
  def template do
    ~HOLO"derived = {@derived_token}"
  end
end
