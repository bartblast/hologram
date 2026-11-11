defmodule Hologram.Test.Fixtures.Page.Module21 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Component.Module39

  route "/hologram-test-fixtures-page-module21"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    <Module39 />
    """
  end
end
