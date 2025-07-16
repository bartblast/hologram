defmodule Hologram.Test.Fixtures.Router.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-router-module1/:a/:b"

  param :a, :integer
  param :b, :atom

  layout Hologram.Test.Fixtures.LayoutWithRuntime

  @impl Page
  def template do
    ~HOLO"Module1 page, a = {inspect(@a)}, b = {inspect(@b)}"
  end
end
