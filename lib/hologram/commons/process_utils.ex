defmodule Hologram.Commons.ProcessUtils do
  @doc """
  Tells whether the process with the given name is running.

  ## Examples

      iex> running?(:my_process)
      true
  """
  @spec running?(atom) :: boolean
  def running?(name) do
    pid = Process.whereis(name)
    if pid, do: Process.alive?(pid), else: false
  end
end
