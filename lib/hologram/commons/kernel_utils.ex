defmodule Hologram.Commons.KernelUtils do
  @moduledoc false

  @doc """
  Inspects the given argument according to the Inspect protocol.
  Maps inspection is deterministic by sorting their key-value pairs.
  """
  @spec inspect(any) :: String.t()
  def inspect(term) do
    Kernel.inspect(term, custom_options: [sort_maps: true])
  end
end
