defmodule Hologram.Compiler.TypeEncoder do
  import Hologram.Commons.Encoder
  alias Hologram.Compiler.{Context, Generator, Opts}

  defmacro __using__(_) do
    quote do
      import Hologram.Compiler.TypeEncoder
    end
  end

  def encode_as_array(data, %Context{} = context, %Opts{} = opts) do
    Enum.map(data, &Generator.generate(&1, context, opts))
    |> Enum.join(", ")
    |> wrap_with_array()
  end
end
