defmodule HologramFeatureTests.PagesTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Pages.TemplateFilePage
  alias HologramFeatureTests.Pages.TemplateFunctionPage

  feature "template defined in function", %{session: session} do
    session
    |> visit(TemplateFunctionPage)
    |> assert_text("Template defined in function")
  end

  feature "template defined in file", %{session: session} do
    session
    |> visit(TemplateFilePage)
    |> assert_text("Template defined in file")
  end
end
