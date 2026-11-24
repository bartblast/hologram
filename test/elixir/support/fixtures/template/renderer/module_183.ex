# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module183 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.Renderer.Module138
  alias Hologram.Test.Fixtures.Template.Renderer.Module180

  route "/hologram-test-fixtures-template-renderer-module183"

  layout Hologram.Test.Fixtures.Template.Renderer.Module49

  state :user_id, :string

  @impl Page
  def init(params, component, _server) do
    put_state(component, :user_id, params.user_id)
  end

  @impl Page
  def template do
    ~HOLO"""
    <Module180 cid="signing_in" user_id={@user_id} />
    <Module138 />
    """
  end
end
