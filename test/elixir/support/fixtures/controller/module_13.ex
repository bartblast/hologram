defmodule Hologram.Test.Fixtures.Controller.Module13 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module13"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, server) do
    put_state(component, subscription_count: length(server.subscriptions))
  end

  @impl Page
  def template do
    ~HOLO"""
    subscription_count = {@subscription_count}
    """
  end
end
