defmodule Hologram.Test.Fixtures.Page.Module15 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Component.Module34

  route "/hologram-test-fixtures-page-module15"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    <Module34 />
    """
  end
end
