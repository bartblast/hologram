defmodule Hologram.Test.Fixtures.Page.Module12 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Component.Module26

  route "/hologram-test-fixtures-page-module12"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    <Module26 />
    """
  end
end
