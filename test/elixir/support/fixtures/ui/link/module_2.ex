defmodule Hologram.Test.Fixtures.UI.Link.Module2 do
  use Hologram.Page

  param :abc, :integer
  param :xyz, :integer

  route "/hologram-test-fixtures-ui-link-module2/:abc/:xyz"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO""
  end
end
