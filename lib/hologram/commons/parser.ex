defmodule Hologram.Commons.Parser do
  @callback parse(String.t()) :: {:ok, term} | {:error, term}

  defmacro __using__(_) do
    quote do
      @behaviour Hologram.Commons.Parser

      @doc """
      Uses the parse/1 implementation of the module to which it is included to parse the given source code.
      Raises an error if the source code is invalid.
      """
      def parse!(code) do
        case parse(code) do
          {:ok, result} ->
            result

          _ ->
            raise """
            Invalid code:
            -----
            #{code}
            -----
            """
        end
      end

      @doc """
      Uses the parse/1 implementation of the module to which it is included to parse the source code in the given file path.
      """
      def parse_file(file_path) do
        file_path
        |> File.read!()
        |> parse()
      end

      @doc """
      Uses the parse/1 implementation of the module to which it is included to parse the source code in the given file path.
      Raises an error if the source code is invalid.
      """
      def parse_file!(file_path) do
        file_path
        |> File.read!()
        |> parse!()
      end
    end
  end
end
