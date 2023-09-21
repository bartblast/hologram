defmodule Hologram.Test.Fixtures.Runtime.Router.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-router-module1"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~H"""
    page Hologram.Test.Fixtures.Runtime.Router.Module1 template
    """
  end
end
