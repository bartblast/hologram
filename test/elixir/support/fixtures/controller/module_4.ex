defmodule Hologram.Test.Fixtures.Controller.Module4 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-controller-module4"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO""
  end
end
