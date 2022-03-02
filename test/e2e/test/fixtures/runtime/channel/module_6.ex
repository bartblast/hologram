defmodule HologramE2E.Test.Fixtures.Runtime.Channel.Module6 do
  use Hologram.Page

  route "/test-route-6"

  def init do
    %{}
  end

  def template do
    ~H"""
    """
  end

  def command(:test_command, _params) do
    {:test_action_target_id, :test_action, a: 1, b: 2}
  end
end
