defmodule Hologram.Test.Fixtures.Page.Module18 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module84

  route "/hologram-test-fixtures-page-module18"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    <Module84 />
    """
  end
end
