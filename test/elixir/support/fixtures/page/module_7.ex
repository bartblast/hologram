defmodule Hologram.Test.Fixtures.Page.Module7 do
  use Hologram.Page

  param :a, :string
  param :b, :integer

  route "/hologram-test-fixtures-page-module7/:a/:b"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO""
  end
end
