defmodule Hologram.Test.Fixtures.Controller.Module12 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-controller-module12"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, server) do
    {component,
     put_broadcast(server, {:user, "test-broadcast-user"}, :page_init_broadcast, text: "hi")}
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
