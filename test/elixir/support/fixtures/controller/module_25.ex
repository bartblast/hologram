defmodule Hologram.Test.Fixtures.Controller.Module25 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module25"

  layout LayoutFixture

  @impl Page
  def middleware(server) do
    put_status(server, :forbidden)
  end

  @impl Page
  def template do
    ~HOLO"Module25"
  end
end
