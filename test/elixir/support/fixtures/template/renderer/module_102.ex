defmodule Hologram.Test.Fixtures.Template.Renderer.Module102 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module102"

  state :a, :integer, default: 1
  state :b, :string, default: "abc"
  state :c, :map

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"page state_a = {@a}, state_b = {@b}"
  end
end
