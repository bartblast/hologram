defmodule Hologram.Test.Fixtures.Controller.Module9 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module9"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, server) do
    put_state(component, session_value: get_session(server, "my_session_key"))
  end

  @impl Page
  def template do
    ~HOLO"""
    session = {@session_value}
    """
  end
end
