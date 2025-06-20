defmodule Hologram.Test.Fixtures.Connection.Module3 do
  use Hologram.Page

  route "/hologram-test-fixtures-connection-module3/:a/:b"

  param :a, :integer
  param :b, :integer

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"page Module3 template, params: a = {@a}, b = {@b}"
  end
end
