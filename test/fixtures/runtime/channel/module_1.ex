defmodule Hologram.Test.Fixtures.Runtime.Channel.Module1 do
  def command(:test_command, _params) do
    :test_action
  end
end
