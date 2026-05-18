defmodule Hologram.Test.Fixtures.Controller.Module19 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module19"

  layout LayoutFixture

  @impl Page
  def init(_params, component, server) do
    server =
      server
      |> put_subscription(:room_a)
      |> delete_subscription(:room_a)

    {component, server}
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
