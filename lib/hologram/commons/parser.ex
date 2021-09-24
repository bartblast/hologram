defmodule Hologram.Commons.Parser do
  defmacro __using__(_) do
    quote do
      def parse!(str) do
        case parse(str) do
          {:ok, ast} ->
            ast

          _ ->
            raise "Invalid code\n-----\n#{str}\n-----"
        end
      end

      def parse_file(filepath) do
        filepath
        |> File.read!()
        |> parse()
      end

      def parse_file!(filepath) do
        filepath
        |> File.read!()
        |> parse!()
      end
    end
  end
end
