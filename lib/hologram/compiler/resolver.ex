defmodule Hologram.Compiler.Resolver do
  @doc """
  Resolves module.
  """
  def resolve(module, aliases) do
    resolved = Enum.find(aliases, &(&1.as == module))
    if resolved, do: resolved.module, else: module
  end
end
