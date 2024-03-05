defmodule Hologram.Test.Fixtures.LayoutFixture do
  use Hologram.Component

  @impl Component
  def template do
    ~H"<slot />"
  end
end
