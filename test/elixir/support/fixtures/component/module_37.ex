defmodule Hologram.Test.Fixtures.Component.Module37 do
  use Hologram.Component

  prop :count, :integer
  prop :theme, :string, from_context: {Hologram.Test.Fixtures.Component.Module37, :theme}

  state :step, :integer

  @impl Component
  def template do
    ~HOLO""
  end
end
