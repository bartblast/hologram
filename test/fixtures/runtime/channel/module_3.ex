defmodule Hologram.Test.Fixtures.Runtime.Channel.Module3 do
  use Hologram.Page

  def init do
    %{}
  end

  def template do
    ~H"""
    """
  end
  
  def command(:test_command, _params) do
    {:test_action, a: 1, b: 2}
  end
end
