defmodule Hologram.Template.Parser do
  use Hologram.Commons.Parser

  def parse(markup) do
    result =
      ("<root>" <> fix_quotes(markup) <> "</root>")
      |> Saxy.SimpleForm.parse_string()

    case result do
      {:ok, {"root", [], nodes}} ->
        {:ok, nodes}

      _ ->
        result
    end
  end

  defp fix_quotes(str) do
    regex = ~r/=(\{.+\})/U
    Regex.replace(regex, str, "=\"\\1\"")
  end
end
