# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module38 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.Module37

  def template do
    ~HOLO"""
    <Module37 size={:small} label="abc" free={@anything} />
    """
  end
end
