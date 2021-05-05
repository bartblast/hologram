defmodule Hologram.Compiler.MapTypeGenerator do
  alias Hologram.Compiler.Generator
  alias Hologram.Compiler.MapKeyGenerator

  def generate(data, context) do
    "{ type: 'map', data: #{generate_data(data, context)} }"
  end

  def generate_data(data, context) do
    fields =
      Enum.map(data, fn {k, v} ->
        "'#{MapKeyGenerator.generate(k, context)}': #{Generator.generate(v, context)}"
      end)
      |> Enum.join(", ")

    if fields != "" do
      "{ #{fields} }"
    else
      "{}"
    end
  end
end
