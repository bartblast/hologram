defmodule Hologram.Test.Fixtures.UI.Link.Module3 do
  use Hologram.Page

  param :a, :string
  param :b, :string

  route "/hologram-test-fixtures-ui-link-module3/:a/:b"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO""
  end
end
