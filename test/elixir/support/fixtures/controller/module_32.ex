# A page whose params are not in its route, so they can only arrive through the query string.
defmodule Hologram.Test.Fixtures.Controller.Module32 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module32"

  param :param_a, :string
  param :param_b, :integer

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    param_a = {@param_a}, param_b = {@param_b}
    """
  end
end
