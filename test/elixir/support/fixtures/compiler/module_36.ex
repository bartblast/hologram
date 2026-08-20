# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module36 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.Module35

  def template do
    ~HOLO"""
    <Module35 />
    """
  end
end
