defmodule Hologram.Test.Fixtures.Runtime.Channel.Module2 do
  use Hologram.Page

  route "/test-route-2"

  def init(_params, _conn) do
    %{}
  end

  def template do
    ~H"""
    """
  end

  def command(:test_command, params) do
    params =
      Enum.map(params, fn {key, value} -> {key, 10 * value} end)
      |> Enum.into([])

    {:test_action, params}
  end
end
