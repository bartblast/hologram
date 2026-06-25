# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module24 do
  use Hologram.Component

  middleware :enrich

  def enrich(server, _opts) do
    put_stash(server, :marker, :injected_by_middleware)
  end

  @impl Component
  def command(:my_command, _params, server) do
    put_action(server, :my_action, marker: get_stash(server, :marker))
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
