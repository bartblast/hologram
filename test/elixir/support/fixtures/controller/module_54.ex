defmodule Hologram.Test.Fixtures.Controller.Module54 do
  use Hologram.Page

  # Sets a user id the server refuses, which is what the tests check.
  @dialyzer {:nowarn_function, init: 3}

  route "/hologram-test-fixtures-controller-module54"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, server) do
    {component, %{server | user_id: false}}
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
