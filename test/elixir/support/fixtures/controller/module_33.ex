defmodule Hologram.Test.Fixtures.Controller.Module33 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module33"

  layout Hologram.Test.Fixtures.LayoutWithRuntime

  @impl Page
  def init(_params, component, _server) do
    put_state(component, :date, ~D[2026-10-05])
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
