defmodule App1.HomePageTest do
  use App1.TestCase, async: true

  feature "renders content defined in the endpoint app", %{session: session} do
    session
    |> visit(App1.HomePage)
    |> assert_text("Umbrella home page")
  end

  feature "runs an action calling a sibling app's code", %{session: session} do
    session
    |> visit(App1.HomePage)
    |> click(button("Fetch app_2 message"))
    |> assert_text(css("#result"), "Hello from app_2!")
  end
end
