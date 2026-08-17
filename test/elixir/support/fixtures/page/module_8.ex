defmodule Hologram.Test.Fixtures.Page.Module8 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Component.Module21

  route "/hologram-test-fixtures-page-module8"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    <Module21 />
    """
  end
end
