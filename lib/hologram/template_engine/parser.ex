defmodule Hologram.TemplateEngine.Parser do
  use Hologram.Parser

  def parse(str) do
    Floki.parse_document(str)
  end
end
