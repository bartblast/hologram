defmodule Holograf.Transpiler.Parser do
  def parse(str) do
    Code.string_to_quoted(str)
  end

  def parse!(str) do
    case parse(str) do
      {:ok, ast} ->
        ast

      _ ->
        raise "Invalid code"
    end
  end

  def parse_file(filepath) do
    filepath
    |> File.read!()
    |> parse()
  end
end
