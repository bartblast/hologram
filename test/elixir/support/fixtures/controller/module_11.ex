defmodule Hologram.Test.Fixtures.Controller.Module11 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module11/:param_a/:param_b"

  param :param_a, :string
  param :param_b, :string

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    param_a = {@param_a}, param_b = {@param_b}
    """
  end
end
