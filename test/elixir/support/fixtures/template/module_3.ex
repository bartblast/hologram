# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Module3 do
  use Hologram.Component

  def trusted_html, do: trust_html("<b>component</b>")

  @impl Component
  def template do
    ~HOLO""
  end
end
