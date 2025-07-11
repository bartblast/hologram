defmodule Hologram.Test.Fixtures.Runtime.MessageHandler.Module7 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-message-handler-module7"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, server) do
    put_state(component, cookie_value: get_cookie(server, "test_cookie"))
  end

  @impl Page
  def template do
    ~HOLO"""
    cookie = {@cookie_value}
    """
  end
end
