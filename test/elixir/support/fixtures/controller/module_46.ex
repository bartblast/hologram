# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module46 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module46"

  layout LayoutFixture

  @impl Page
  def init(_params, _component, server) do
    put_response_header(server, "content-security-policy", "script-src 'self'")
  end

  @impl Page
  def template do
    ~HOLO"Module46"
  end
end
