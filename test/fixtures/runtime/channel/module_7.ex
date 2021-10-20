defmodule Hologram.Test.Fixtures.Runtime.Channel.Module7 do
  def command(:test_command, _params) do
    {:test_action_target_id, :test_action}
  end
end
