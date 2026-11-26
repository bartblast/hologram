# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module184 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Entity.Module15

  route "/hologram-test-fixtures-template-renderer-module184"

  layout Hologram.Test.Fixtures.Template.Renderer.Module185

  state :row, :any

  derived :row_token_server_only, :boolean, fn row -> server_only?(row.token) end

  @impl Page
  def init(_params, component, _server) do
    put_state(component, :row, Module15.new(%{token: "tok_page_secret"}))
  end

  @impl Page
  def template do
    ~HOLO"""
    page = {inspect(@row.token)}; derived = {inspect(@row_token_server_only)};
    """
  end
end
