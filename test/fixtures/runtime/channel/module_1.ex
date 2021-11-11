defmodule Hologram.Test.Fixtures.Runtime.Channel.Module1 do
  use Hologram.Page

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
