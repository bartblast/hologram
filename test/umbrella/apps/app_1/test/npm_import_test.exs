defmodule App1.NpmImportTest do
  use App1.TestCase, async: true

  feature "runs an action using an npm package", %{session: session} do
    session
    |> visit(App1.NpmImportPage)
    |> click(button("Add decimals"))
    |> assert_text(css("#result"), "123")
  end
end
