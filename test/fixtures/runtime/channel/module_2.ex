defmodule Hologram.Test.Fixtures.Runtime.Module2 do
  def command(:test_command, params) do
    params =
      Enum.map(params, fn {key, value} -> {key, 10 * value} end)
      |> Enum.into([])

    {:test_action, params}
  end
end
