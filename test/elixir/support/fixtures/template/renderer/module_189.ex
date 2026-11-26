# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module189 do
  use Hologram.Component

  prop :row, :any, from_context: {:module_188, :row}

  derived :row_token_server_only, :boolean, fn row -> server_only?(row.token) end

  @impl Component
  def template do
    ~HOLO"""
    context = {inspect(@row.token)}; derived = {inspect(@row_token_server_only)}
    """
  end
end
