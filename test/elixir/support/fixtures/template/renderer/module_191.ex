# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module191 do
  use Hologram.Component

  prop :row, :any

  state :row_token_server_only, :boolean

  @impl Component
  def init(props, component, _server) do
    put_state(component, :row_token_server_only, server_only?(props.row.token))
  end

  @impl Component
  def template do
    ~HOLO"""
    child init = {inspect(@row_token_server_only)}
    """
  end
end
