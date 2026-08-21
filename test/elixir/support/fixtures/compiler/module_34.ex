# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module34 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.Module31

  def template do
    ~HOLO"""
    <Module31 ...{@props} />
    """
  end
end
