# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module30 do
  use Hologram.Component

  alias Hologram.Auth

  middleware :capture_actor

  def capture_actor(server, _opts) do
    put_stash(server, :actor, Auth.user_id())
  end

  @impl Component
  def command(:my_command_reporting_middleware_actor, _params, server) do
    put_action(server, :my_action, actor: get_stash(server, :actor))
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
