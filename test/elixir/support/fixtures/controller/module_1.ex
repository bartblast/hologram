defmodule Hologram.Test.Fixtures.Controller.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-controller-module1/:aaa/ccc/:bbb"

  param :aaa, :integer
  param :bbb, :integer

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    param_aaa = {@aaa}, param_bbb = {@bbb}
    """
  end
end
