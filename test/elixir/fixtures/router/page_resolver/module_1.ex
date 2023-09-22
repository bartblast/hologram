defmodule Hologram.Test.Fixtures.Router.PageResolver.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-router-page-resolver-module1"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~H"""
    page Hologram.Test.Fixtures.Router.PageResolver.Module1 template
    """
  end
end
