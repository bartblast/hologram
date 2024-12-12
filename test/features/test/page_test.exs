defmodule HologramFeatureTests.PagesTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.Pages.TemplateFunctionPage

  feature "template defined in function", %{session: session} do
    session
    |> visit(TemplateFunctionPage)
    |> assert_text("Template defined in function")
  end
end
