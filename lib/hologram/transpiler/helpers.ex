defmodule Hologram.Transpiler.Helpers do
  def class_name(module) do
    module_name(module)
    |> String.replace(".", "")
  end

  def module_name(module) do
    Enum.join(module, ".")
  end
end
