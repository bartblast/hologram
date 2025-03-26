defmodule Hologram.Test.Fixtures.Page.Module7 do
  use Hologram.Page

  param :a, :string
  param :b, :integer, opt_1: 111, opt_2: 222

  route "/hologram-test-fixtures-page-module7/:a/:b"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO""
  end
end
