defmodule Hologram.Test.Fixtures.Runtime.Channel.Module5 do
  use Hologram.Page

  route "/test-route-5"
  layout Hologram.Test.Fixtures.Runtime.Channel.Module8

  def init(_params, _conn) do
    %{}
  end

  def template do
    ~H"""
      test_template
    """
  end
end
