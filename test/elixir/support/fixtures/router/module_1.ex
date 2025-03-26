defmodule Hologram.Test.Fixtures.Router.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-router-module1"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"page Hologram.Test.Fixtures.Router.Module1 template"
  end
end
