defmodule Holograf.Transpiler.Parser do
  def parse!(str) do
    case Code.string_to_quoted(str) do
      {:ok, ast} ->
        ast

      _ ->
        raise "Invalid code"
    end
  end
end
