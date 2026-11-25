# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module55 do
  use Hologram.Component

  # Sets a user id the server refuses, which is what the tests check.
  @dialyzer {:nowarn_function, authenticate: 2}

  middleware :authenticate

  def authenticate(server, _opts) do
    put_status(%{server | user_id: false}, :forbidden)
  end

  @impl Component
  def command(:my_command, _params, _server) do
    raise "command must not run when middleware produces a terminal response"
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
