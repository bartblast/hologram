defmodule Hologram.Compiler.MapTypeGenerator do
  import Hologram.Commons.Encoder
  alias Hologram.Compiler.{Context, Generator, MapKeyGenerator, Opts}

  def generate(data, %Context{} = context, %Opts{} = opts) do
    "{ type: 'map', data: #{generate_data(data, context, opts)} }"
  end

  def generate_data(data, %Context{} = context, %Opts{} = opts) do
    Enum.map(data, fn {k, v} ->
      "'#{MapKeyGenerator.generate(k, context)}': #{Generator.generate(v, context, opts)}"
    end)
    |> Enum.join(", ")
    |> wrap_with_object()
  end
end
