defmodule Hologram.Test.Fixtures.Controller.Module2 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module2"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, server) do
    put_state(component, cookie_value: get_cookie(server, "my_cookie"))
  end

  @impl Page
  def template do
    ~HOLO"""
    cookie = {@cookie_value}
    """
  end
end
