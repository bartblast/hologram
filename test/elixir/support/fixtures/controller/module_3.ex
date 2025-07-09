defmodule Hologram.Test.Fixtures.Controller.Module3 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module3"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, _component, server) do
    put_cookie(server, "my_cookie", 123)
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
