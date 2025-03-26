defmodule Hologram.Test.Fixtures.UI.Link.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-ui-link-module1"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO""
  end
end
