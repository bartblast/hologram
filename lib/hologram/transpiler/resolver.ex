defmodule Hologram.Transpiler.Resolver do
  def resolve_aliased_module(module, aliases) do
    resolved = Enum.find(aliases, &(&1.as == module))
    if resolved, do: resolved.module, else: nil
  end
end
