defmodule Hologram.Test.Fixtures.Runtime.Channel.Module5 do
  use Hologram.Page

  route("/test-route")

  def state do
    %{}
  end

  def template do
    ~H"""
      test_template
    """
  end
end
