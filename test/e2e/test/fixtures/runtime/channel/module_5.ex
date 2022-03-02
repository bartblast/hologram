defmodule HologramE2E.Test.Fixtures.Runtime.Channel.Module5 do
  use Hologram.Page

  route "/test-route-5"
  layout HologramE2E.Test.Fixtures.Runtime.Channel.Module8

  def init do
    %{}
  end

  def template do
    ~H"""
      test_template
    """
  end
end
