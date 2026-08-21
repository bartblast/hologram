# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module30 do
  use Hologram.Component

  def template do
    ~HOLO"""
    <{@module} a="1" />
    """
  end
end
