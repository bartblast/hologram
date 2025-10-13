defmodule Hologram.LiveReload.Reloader do
  @moduledoc false

  @doc """
  Recompiles Hologram bundles.

  This is a simple wrapper around Mix.Tasks.Compile.Hologram.run/1.
  """
  @spec recompile_hologram(keyword) :: :ok
  def recompile_hologram(opts \\ []) do
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    Mix.Tasks.Compile.Hologram.run(opts)
  end
end
