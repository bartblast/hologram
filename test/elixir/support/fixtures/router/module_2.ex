defmodule Hologram.Test.Fixtures.Router.Module2 do
  use Hologram.Component

  def command(:my_command, _params, server) do
    %{server | next_action: nil}
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
