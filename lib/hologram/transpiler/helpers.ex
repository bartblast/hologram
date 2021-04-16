defmodule Hologram.Transpiler.Helpers do
  def module_name(module) do
    Enum.join(module, ".")
  end
end
