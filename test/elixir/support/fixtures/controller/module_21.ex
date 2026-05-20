defmodule Hologram.Test.Fixtures.Controller.Module21 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module21"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, server) do
    {component, %{server | user_id: 7}}
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
