defmodule Hologram.Test.Fixtures.Router.PageModuleResolver.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-router-pagemoduleresolver-module1"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    page Hologram.Test.Fixtures.Router.PageModuleResolver.Module1 template
    """
  end
end
