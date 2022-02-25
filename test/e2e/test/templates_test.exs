defmodule Hologram.Features.TemplatesTest do
  use Hologram.Test.E2ECase, async: false

  @moduletag :e2e

  describe "if directive" do
    feature "element node", %{session: session} do
      session
      |> visit("/e2e/page-9")
      |> assert_has(css("#div-1", text: "Element displayed"))
      |> refute_has(css("#div-2", text: "Element not displayed"))
    end
  end
end
