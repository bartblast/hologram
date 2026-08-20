defmodule Hologram.Test.Fixtures.Page.Module9 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Component.Module16
  alias Hologram.Test.Fixtures.Component.Module18
  alias Hologram.Test.Fixtures.Component.Module24

  route "/hologram-test-fixtures-page-module9"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    <Module16 />
    <Module18 />
    <Module24 min_b={123} />
    """
  end
end
