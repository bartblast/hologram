defmodule Hologram.Features.DocumentTest do
  use Hologram.E2ECase, async: false

  @moduletag :e2e

  feature "component with nested slots", %{session: session} do
    session
    |> visit("/e2e/page-3")
    |> click(css("#update-button"))

    page_source = page_source(session)

    assert page_source =~ "in page template: abc"
    assert page_source =~ "in component 1 template header"
    assert page_source =~ "in component 1 slot: bcd"
    assert page_source =~ "in component 2 template header"
    assert page_source =~ "in component 2 slot: xyz"
    assert page_source =~ "in component 2 template footer"
    assert page_source =~ "in component 1 template footer"
  end
end
