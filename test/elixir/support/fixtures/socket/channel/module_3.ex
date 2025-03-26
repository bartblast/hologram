defmodule Hologram.Test.Fixtures.Socket.Channel.Module3 do
  use Hologram.Page

  route "/hologram-test-fixtures-socket-channel-module3/:a/:b"

  param :a, :integer
  param :b, :integer

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"page Module3 template, params: a = {@a}, b = {@b}"
  end
end
