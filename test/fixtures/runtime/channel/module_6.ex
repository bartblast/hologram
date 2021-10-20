defmodule Hologram.Test.Fixtures.Runtime.Channel.Module6 do
  def command(:test_command, _params) do
    {:test_action_target_id, :test_action, a: 1, b: 2}
  end
end
