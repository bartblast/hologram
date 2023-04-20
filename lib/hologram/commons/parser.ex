defmodule Hologram.Commons.Parser do
  @callback parse(binary) :: {:ok, any} | {:error, any}

  defmacro __using__(_) do
    quote do
      @behaviour Hologram.Commons.Parser

      @doc """
      Uses the parse/1 implementation of the module to which it is included to parse the given source code.
      Raises an error if the source code is invalid.
      """
      @spec parse!(binary) :: any
      def parse!(code) do
        case parse(code) do
          {:ok, result} ->
            result

          _fallback ->
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
      @spec parse_file(binary) :: {:ok, any} | {:error, any}
      def parse_file(file_path) do
        file_path
        |> File.read!()
        |> parse()
      end

      @doc """
      Uses the parse/1 implementation of the module to which it is included to parse the source code in the given file path.
      Raises an error if the source code is invalid.
      """
      @spec parse_file!(binary) :: any
      def parse_file!(file_path) do
        file_path
        |> File.read!()
        |> parse!()
      end
    end
  end
end
