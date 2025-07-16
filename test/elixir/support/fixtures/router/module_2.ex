defmodule Hologram.Test.Fixtures.Router.Module2 do
  use Hologram.Page

  route "/hologram-test-fixtures-router-module2"

  param :a, :integer
  param :b, :atom

  layout Hologram.Test.Fixtures.LayoutWithRuntime

  @impl Page
  def template do
    ~HOLO"Module2 page, a = {inspect(@a)}, b = {inspect(@b)}"
  end
end
