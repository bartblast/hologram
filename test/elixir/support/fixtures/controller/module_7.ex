defmodule Hologram.Test.Fixtures.Controller.Module7 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module7/:a/:b"

  param :a, :integer
  param :b, :integer

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"page Module7 template, params: a = {@a}, b = {@b}"
  end
end
