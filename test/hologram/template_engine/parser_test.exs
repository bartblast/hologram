defmodule Hologram.TemplateEngine.ParserTest do
  use ExUnit.Case
  alias Hologram.TemplateEngine.Parser

  describe "parse/1" do
    test "valid html" do
      assert {:ok, _} = Parser.parse("<div></div>")
    end

    # TODO: find invalid case
    # test "invalid html" do
    #   assert {:error, _} = Parser.parse("<div ")
    # end
  end
end
