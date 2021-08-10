defmodule Hologram.Compiler.ModuleTypeDecoder do
  def decode(class) do
    String.replace(class, "_", ".")
    |> String.to_existing_atom()
  end
end
