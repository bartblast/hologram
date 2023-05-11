defmodule Hologram.Commons.Encoder do
  alias Hologram.Compiler.{Context, JSEncoder, MapKeyEncoder, Opts}
  alias Hologram.Compiler.IR.Block
  alias Hologram.Compiler.IR.Variable

  defmacro __using__(_) do
    quote do
      import Hologram.Commons.Encoder
    end
  end

  def encode_args(args, context, opts) do
    Enum.map(args, fn arg ->
      case arg do
        %Variable{name: name} ->
          name

        _ ->
          JSEncoder.encode(arg, context, opts)
      end
    end)
    |> Enum.join(", ")
  end

  def encode_as_arrow_function(%Block{} = block, context, opts) do
    """
    () => {
    #{JSEncoder.encode(block, context, opts)}
    }\
    """
  end

  def encode_as_arrow_function(expr, context, opts) do
    %Block{expressions: [expr]}
    |> encode_as_arrow_function(context, opts)
  end

  def encode_identifier(name) do
    to_string(name)
    |> String.replace("?", "$question")
    |> String.replace("!", "$bang")
  end

  def encode_map_data(data, %Context{} = context, %Opts{} = opts) do
    Enum.map(data, fn {k, v} ->
      "'#{MapKeyEncoder.encode(k, context, opts)}': #{JSEncoder.encode(v, context, opts)}"
    end)
    |> Enum.join(", ")
    |> wrap_with_object()
  end

  def encode_primitive_key(type, value) do
    "~#{type}[#{value}]"
  end

  def encode_vars(bindings, context, opts) do
    bindings
    |> Enum.map(&JSEncoder.encode(&1, context, opts))
    |> Enum.join("\n")
  end

  def wrap_with_object(data) do
    if data != "", do: "{ #{data} }", else: "{}"
  end
end
