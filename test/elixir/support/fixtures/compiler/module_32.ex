# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module32 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.Module31

  def template do
    ~HOLO"""
    <Module31 size={@size} />
    """
  end
end
