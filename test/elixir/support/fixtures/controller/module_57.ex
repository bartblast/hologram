# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module57 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module57"

  layout Hologram.Test.Fixtures.LayoutWithRuntime

  @impl Page
  def init(_params, component, server) do
    {component, put_user_id(server, 7)}
  end

  @impl Page
  def template do
    ~HOLO"Module57 page"
  end
end
