defmodule Hologram.Test.Fixtures.Page.Module23 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Component.Module54

  route "/hologram-test-fixtures-page-module23"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    <Module54 min_b={1} />
    """
  end
end
