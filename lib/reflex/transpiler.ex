defmodule Reflex.Transpiler do
  def parse_file(path) do
    path
    |> File.read!()
    |> Code.string_to_quoted()
  end
end
