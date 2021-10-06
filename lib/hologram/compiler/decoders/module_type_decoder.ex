defmodule Hologram.Compiler.ModuleTypeDecoder do
  def decode(%{"className" => class_name}) do
    String.replace(class_name, "_", ".")
    |> String.to_existing_atom()
  end
end
