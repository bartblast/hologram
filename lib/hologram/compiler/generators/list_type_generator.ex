defmodule Hologram.Compiler.ListTypeGenerator do
  alias Hologram.Compiler.{Context, Generator}

  def generate(data, %Context{} = context, opts) do
    "{ type: 'list', data: #{generate_data(data, context, opts)} }"
  end

  def generate_data(data, %Context{} = context, opts) do
    data =
      Enum.map(data, &Generator.generate(&1, context, opts))
      |> Enum.join(", ")

    if data != "" do
      "[ #{data} ]"
    else
      "[]"
    end
  end
end
