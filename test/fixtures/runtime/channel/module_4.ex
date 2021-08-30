defmodule Hologram.Test.Fixtures.Runtime.Channel.Module4 do
  def command(:test_command, params) do
    :"test_action_#{params.a}"
  end
end
