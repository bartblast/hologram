defmodule Hologram.Test.Fixtures.Controller.Module22 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module22"

  layout Hologram.Test.Fixtures.LayoutFixture

  # Fixture intentionally raises after a user_id change to exercise the
  # skip-on-raise path; Dialyzer flags this as no_return otherwise.
  @dialyzer {:no_return, init: 3}

  @impl Page
  def init(_params, _component, server) do
    server = %{server | user_id: 7}
    raise "boom"
    server
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
