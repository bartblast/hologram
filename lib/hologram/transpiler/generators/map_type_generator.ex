defmodule Hologram.Transpiler.Generators.MapTypeGenerator do
  alias Hologram.Transpiler.Generator
  alias Hologram.Transpiler.Generators.MapKeyGenerator

  def generate(data) do
    "{ type: 'map', data: #{generate_data(data)} }"
  end

  def generate_data(data) do
    fields =
      Enum.map(data, fn {k, v} ->
        "'#{MapKeyGenerator.generate(k)}': #{Generator.generate(v)}"
      end)
      |> Enum.join(", ")

    if fields != "" do
      "{ #{fields} }"
    else
      "{}"
    end
  end
end
