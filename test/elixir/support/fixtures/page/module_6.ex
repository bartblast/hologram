defmodule Hologram.Test.Fixtures.Page.Module6 do
  use Hologram.Page

  param :a, :atom
  param :b, :float
  param :c, :integer
  param :d, :string
  param :e, :id

  route "/hologram-test-fixtures-page-module6/:a/:b/:c/:d/:e"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO""
  end
end
