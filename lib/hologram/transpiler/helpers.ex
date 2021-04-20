defmodule Hologram.Transpiler.Helpers do
  def class_name(module) do
    module_name(module)
    |> String.replace(".", "")
  end

  def fully_qualified_module(module) do
    ([:"Elixir"] ++ module)
    |> Enum.join(".")
    |> String.to_existing_atom()
  end

  def module_name(module) do
    Enum.join(module, ".")
  end

  def module_name_atom(module) do
    module_name(module)
    |> String.to_atom()
  end
end
