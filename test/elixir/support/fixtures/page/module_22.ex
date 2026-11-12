defmodule Hologram.Test.Fixtures.Page.Module22 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Component.Module44
  alias Hologram.Test.Fixtures.Component.Module48

  route "/hologram-test-fixtures-page-module22"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    <Module44 />
    <Module48 />
    """
  end
end
