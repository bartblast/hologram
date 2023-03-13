defmodule HologramE2E.TypesTest do
  use HologramE2E.TestCase, async: false

  alias HologramE2E.Types.AnonymousFunctionPage
  alias HologramE2E.Types.FloatPage

  describe "anonymous function" do
    feature "regular syntax", %{session: session} do
      session
      |> visit(AnonymousFunctionPage)
      |> click(css("#button_regular_syntax"))
      |> assert_has(css("#text", text: "Result = true"))
    end

    # TODO: implement
    # feature "shorthand syntax"
  end

  describe "float" do
    feature "encoding", %{session: session} do
      session
      |> visit(FloatPage)
      |> click(css("#button_test_encoding"))
      |> assert_has(css("#text_encoding_result", text: "Result encoding = 1.23"))
    end

    feature "decoding", %{session: session} do
      session
      |> visit(FloatPage)
      |> click(css("#button_test_decoding"))
      |> assert_has(css("#text_decoding_result", text: "Result decoding = 12.34"))
    end
  end
end
