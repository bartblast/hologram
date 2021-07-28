defmodule Hologram.Compiler.TypeEncoder do
  alias Hologram.Compiler.{Context, Generator}

  defmacro __using__(_) do
    quote do
      import Hologram.Compiler.TypeEncoder
    end
  end

  def encode_as_list(data, %Context{} = context, opts) do
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
