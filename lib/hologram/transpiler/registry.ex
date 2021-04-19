defmodule Hologram.Transpiler.Registry do
  def has_function?(registry, module, function, arity) do
    (registry[module] || [])
    |> Enum.any?(&(&1.name == function && &1.arity == arity))
  end
end
