defmodule Hologram.Test.Fixtures.Controller.Module35 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module35"

  layout Hologram.Test.Fixtures.LayoutWithRuntime

  @impl Page
  def init(_params, component, server) do
    new_server =
      server
      |> put_subscription({:instance, server.instance_id})
      |> put_broadcast({:instance, server.instance_id}, :test_action, time: ~T[12:34:56])

    {component, new_server}
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
