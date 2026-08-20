# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module104 do
  use Hologram.Page

  param :label, :string

  route "/hologram-test-fixtures-template-renderer-module104/:label"

  layout Hologram.Test.Fixtures.Template.Renderer.Module49

  # A param reaching the markup, as text and inside an attribute value - the two places a
  # placeholder token means nothing and has to stay the text it is.
  @impl Page
  def template do
    ~HOLO"""
    <div title={@label}>{@label}</div>
    """
  end
end
