defmodule HologramE2E.Test.Fixtures.Runtime.Channel.Module1 do
  use Hologram.Page

  route "/test-route-1"

  def init do
    %{}
  end

  def template do
    ~H"""
    """
  end

  def command(:test_command, _params) do
    :test_action
  end
end
