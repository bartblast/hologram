defmodule Hologram.Test.Fixtures.Page.Module20 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Component.Module38

  route "/hologram-test-fixtures-page-module20"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    <Module38 />
    """
  end
end
