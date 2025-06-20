defmodule Hologram.Test.Fixtures.Runtime.MessageHandler.Module6 do
  use Hologram.Component
  alias Hologram.Component.Action

  def command(:my_command_6, _params, server) do
    action = %Action{
      name: :my_action_6,
      params: %{func: fn x -> x + 1 end},
      target: nil
    }

    %{server | next_action: action}
  end

  def template do
    ~HOLO""
  end
end
