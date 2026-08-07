defmodule App3.PageTest do
  use App1.TestCase, async: true

  feature "renders a page defined in a sibling library app", %{session: session} do
    session
    |> visit(App3.Page)
    |> assert_text(css("#message"), "Hello from app_3!")
  end
end
