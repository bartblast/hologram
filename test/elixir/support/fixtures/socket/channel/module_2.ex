defmodule Hologram.Test.Fixtures.Socket.Channel.Module2 do
  use Hologram.Page

  route "/hologram-test-fixtures-socket-channel-module2"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"page Module2 template"
  end
end
