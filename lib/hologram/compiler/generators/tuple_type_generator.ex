defmodule Hologram.Compiler.TupleTypeGenerator do
  alias Hologram.Compiler.{Context, Generator}

  def generate(data, %Context{} = context, opts) do
    "{ type: 'tuple', data: #{generate_data(data, context, opts)} }"
  end

  def generate_data(data, %Context{} = context, opts) do
    fields =
      Enum.map(data, &"#{Generator.generate(&1, context, opts)}")
      |> Enum.join(", ")

    if fields != "" do
      "{ #{fields} }"
    else
      "{}"
    end
  end
end
