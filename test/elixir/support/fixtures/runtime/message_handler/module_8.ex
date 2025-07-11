defmodule Hologram.Test.Fixtures.Runtime.MessageHandler.Module8 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-message-handler-module8"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, server) do
    new_server = put_cookie(server, "test_cookie", "test_value")
    {component, new_server}
  end

  @impl Page
  def template do
    ~HOLO"page Module8 template"
  end
end
