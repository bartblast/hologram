defmodule Hologram.Test.Fixtures.Router.Helpers.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-router-helpers-module1"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO""
  end
end
