defmodule Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module9 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    <nav $ref="menu"></nav><slot />
    """
  end
end
