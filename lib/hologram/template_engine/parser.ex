defmodule Hologram.TemplateEngine.Parser do
  use Hologram.Parser

  def parse(str) do
    fix_quotes(str)
    |> Saxy.SimpleForm.parse_string()
  end

  defp fix_quotes(str) do
    regex = ~r/=(\{\{.+\}\})/U
    Regex.replace(regex, str, "=\"\\1\"")
  end
end
