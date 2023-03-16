defmodule Hologram.Commons.Parser do
  @callback parse(String.t()) :: {:ok, term} | {:error, term}

  defmacro __using__(_) do
    quote do
      @behaviour Hologram.Commons.Parser

      def parse!(str) do
        case parse(str) do
          {:ok, result} ->
            result

          _ ->
            raise """
            Invalid code:
            -----
            #{str}
            -----
            """
        end
      end

      def parse_file(file_path) do
        file_path
        |> File.read!()
        |> parse()
      end

      def parse_file!(file_path) do
        file_path
        |> File.read!()
        |> parse!()
      end
    end
  end
end
