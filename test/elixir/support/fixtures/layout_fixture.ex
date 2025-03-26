defmodule Hologram.Test.Fixtures.LayoutFixture do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"<slot />"
  end
end
