# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module187 do
  use Hologram.Component

  prop :row, :any

  state :copy, :any

  derived :copy_token_server_only, :boolean, fn copy -> server_only?(copy.token) end

  @impl Component
  def init(props, component, _server) do
    put_state(component, :copy, props.row)
  end

  @impl Component
  def template do
    ~HOLO"""
    stateful = {inspect(@copy.token)}; derived = {inspect(@copy_token_server_only)}
    """
  end
end
