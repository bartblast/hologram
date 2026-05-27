defmodule Hologram.Test.Fixtures.Controller.Module20 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Controller.Module16

  route "/hologram-test-fixtures-controller-module20"

  layout Module16

  @impl Page
  def init(_params, _component, server) do
    put_subscription(server, :room_page2)
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
