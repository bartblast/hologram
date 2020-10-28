defmodule Reflex.Transpiler do
  def parse!(str) do
    case Code.string_to_quoted(str) do
      {:ok, ast} ->
        ast

      _ ->
        raise "Invalid code"
    end
  end

  def parse_file(path) do
    path
    |> File.read!()
    |> Code.string_to_quoted()
  end

  def transpile(ast) when is_binary(ast) do
    ast
  end

  def transpile(ast) when is_integer(ast) do
    to_string(ast)
  end
end
