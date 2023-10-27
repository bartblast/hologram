defmodule Hologram.Commons.ProcessUtils do
  @doc """
  Tells whether the process with the given name is running.
  """
  @spec running?(atom) :: boolean
  def running?(name) do
    name
    |> Process.whereis()
    |> then(&(&1 && Process.alive?(&1)))
    |> then(&(&1 || false))
  end
end
