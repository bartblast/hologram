defmodule Hologram.Test.Fixtures.Compiler.Module49 do
  use Hologram.Component

  prop :relationship, :atom, default: :secrets

  @impl Component
  def template do
    ~HOLO""
  end
end
