defmodule Hologram.Test.Fixtures.Runtime.Channel.Module4 do
  use Hologram.Page

  route "/test-route-4"

  def init(_params, _conn) do
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
