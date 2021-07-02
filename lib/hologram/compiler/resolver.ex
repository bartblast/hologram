defmodule Hologram.Compiler.Resolver do
  alias Hologram.Compiler.IR.Alias
  alias Hologram.Compiler.Typespecs, as: T

  @doc """
  Returns the module name segments of a matching aliased module.
  If no matching alias is found, it returns the given module name segments.
  """
  @spec resolve(T.module_name_segments, list(%Alias{})) :: T.module_name_segments

  def resolve(module_name_segments, aliases) do
    resolved = Enum.find(aliases, &(&1.as == module_name_segments))
    if resolved, do: resolved.module, else: module_name_segments
  end
end
