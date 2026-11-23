# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module50 do
  use Hologram.Component

  alias Hologram.Auth
  alias Hologram.Auth.Context

  middleware :capture_actor

  def capture_actor(server, _opts) do
    server
    |> put_stash(:actor, Auth.user_id())
    |> put_stash(:in_session, Context.session?())
  end

  @impl Component
  def command(:my_command_reporting_middleware_actor, _params, server) do
    put_action(server, :my_action, actor: get_stash(server, :actor))
  end

  def command(:my_command_reporting_middleware_session, _params, server) do
    put_action(server, :my_action, in_session: get_stash(server, :in_session))
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
