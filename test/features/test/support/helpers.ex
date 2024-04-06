defmodule HologramFeatureTests.Helpers do
  alias Hologram.Router
  alias Wallaby.Browser

  def visit(session, page_module) do
    visit(session, page_module, [])
  end

  def visit(session, page_module, params) do
    path = Router.Helpers.page_path(page_module, params)
    Browser.visit(session, path)
  end
end
