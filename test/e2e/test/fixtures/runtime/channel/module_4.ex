defmodule HologramE2E.Test.Fixtures.Runtime.Channel.Module4 do
  use Hologram.Page

  route "/test-route-4"

  def init do
    %{}
  end

  def template do
    ~H"""
    """
  end

  def command(:test_command, params) do
    :"test_action_#{params.a}"
  end
end
