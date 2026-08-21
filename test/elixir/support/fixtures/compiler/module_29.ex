# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module29 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.Module27

  def template do
    ~HOLO"""
    <Module27 a="1" ...{@props} />
    """
  end
end
