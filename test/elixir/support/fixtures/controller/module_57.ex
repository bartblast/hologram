# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module57 do
  use Hologram.Page

  alias Hologram.Auth.Context
  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module57"

  layout LayoutFixture

  middleware :report_session

  def report_session(server, _opts) do
    put_response_header(server, "x-in-session", to_string(Context.session?()))
  end

  @impl Page
  def template do
    ~HOLO"Module57"
  end
end
