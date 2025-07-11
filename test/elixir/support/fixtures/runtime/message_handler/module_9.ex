defmodule Hologram.Test.Fixtures.Runtime.MessageHandler.Module9 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-message-handler-module9"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, server) do
    {component, server}
  end

  @impl Page
  def template do
    ~HOLO"page Module9 template"
  end
end
