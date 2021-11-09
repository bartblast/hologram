defmodule Hologram.Features.UITest do
  use Hologram.Test.E2ECase, async: false
  
  @moduletag :e2e

  feature "link", %{session: session} do
    session
    |> visit("/e2e/page-6")
    |> click(css("#test-id"))
    |> assert_has(css("h1", text: "Page 7"))

    assert current_path(session) == "/e2e/page-7"
  end
end
