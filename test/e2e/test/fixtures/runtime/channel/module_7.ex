defmodule HologramE2E.Test.Fixtures.Runtime.Channel.Module7 do
  use Hologram.Page

  route "/test-route-7"

  def init(_params, _conn) do
    %{}
  end

  def template do
    ~H"""
    """
  end

  def command(:test_command, _params) do
    {:test_action_target_id, :test_action}
  end
end
