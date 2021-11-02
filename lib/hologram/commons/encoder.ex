defmodule Hologram.Commons.Encoder do
  alias Hologram.Compiler.{Context, JSEncoder, MapKeyEncoder, Opts}
  alias Hologram.Compiler.IR.{AccessOperator, Variable}

  defmacro __using__(_) do
    quote do
      import Hologram.Commons.Encoder
    end
  end

  def encode_as_array(data, %Context{} = context, %Opts{} = opts) do
    Enum.map(data, &JSEncoder.encode(&1, context, opts))
    |> Enum.join(", ")
    |> wrap_with_array()
  end

  defp encode_expression(expr, idx, expr_count, context, opts) do
    return = if idx == expr_count - 1, do: "return ", else: ""
    "#{return}#{JSEncoder.encode(expr, context, opts)};"
  end

  def encode_expressions(body, context, opts, separator) do
    expr_count = Enum.count(body)

    Enum.with_index(body)
    |> Enum.map(fn {expr, idx} -> encode_expression(expr, idx, expr_count, context, opts) end)
    |> Enum.join(separator)
  end

  def encode_function_name(function_name) do
    to_string(function_name)
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

  def encode_primitive_type(type, value) do
    "{ type: '#{type}', value: #{value} }"
  end

  defp encode_var({name, {idx, path}}, context) do
    acc = "let #{name} = arguments[#{idx}]"

    value =
      Enum.reduce(path, acc, fn type, acc ->
        acc <>
          case type do
            %AccessOperator{key: key} ->
              ".data['#{MapKeyEncoder.encode(key, context, %Opts{})}']"

            %Variable{} ->
              ""
          end
      end)

    "#{value};"
  end

  def encode_vars(bindings, context, separator) do
    Enum.map(bindings, &encode_var(&1, context))
    |> Enum.join(separator)
  end

  def wrap_with_array(data) do
    if data != "", do: "[ #{data} ]", else: "[]"
  end

  def wrap_with_object(data) do
    if data != "", do: "{ #{data} }", else: "{}"
  end
end
