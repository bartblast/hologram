defmodule Hologram.Test.Fixtures.Router.Helpers.Module3 do
  use Hologram.Page

  route "/hologram-test-fixtures-router-helpers-module3/:x/:y"

  param :x, :string
  param :y, :atom

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template, do: ~HOLO""
end
