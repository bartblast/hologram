# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module8 do
  use Hologram.Component
  alias Hologram.Component.Action

  def command(:my_command_8, _params, server) do
    action = %Action{
      name: :my_action_8,
      params: %{func: fn x -> x + 1 end},
      target: nil
    }

    %{server | next_action: action}
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
