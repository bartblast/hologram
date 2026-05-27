defmodule Hologram.Test.Fixtures.Controller.Module15 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module15"

  layout Hologram.Test.Fixtures.LayoutFixture

  # Fixture intentionally raises after put_subscription to exercise the
  # rollback path; Dialyzer flags this as no_return otherwise.
  @dialyzer {:no_return, init: 3}

  @impl Page
  def init(_params, _component, server) do
    server = put_subscription(server, :room_a)
    raise "boom"
    server
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
