defmodule Hologram.Test.Fixtures.Controller.Module10 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module10"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, _component, server) do
    put_session(server, "my_session_key", 123)
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
