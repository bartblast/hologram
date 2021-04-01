defmodule Hologram.TemplateEngine.Parser do
  use Hologram.Parser

  def parse(str) do
    Saxy.SimpleForm.parse_string(str)
  end
end
