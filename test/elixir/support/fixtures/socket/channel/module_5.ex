defmodule Hologram.Test.Fixtures.Socket.Channel.Module5 do
  use Hologram.Page

  route "/hologram-test-fixtures-socket-channel-module5"

  layout Hologram.Test.Fixtures.Socket.Channel.Module4

  @impl Page
  def template do
    ~HOLO"page Module5 template"
  end
end
