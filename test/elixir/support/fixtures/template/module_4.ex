# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Module4 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-module4"

  layout Hologram.Test.Fixtures.Page.Module4

  def trusted_html, do: trust_html("<b>page</b>")

  @impl Page
  def template do
    ~HOLO""
  end
end
