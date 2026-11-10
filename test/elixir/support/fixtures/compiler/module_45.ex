# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module45 do
  use Hologram.Component

  def template do
    ~HOLO"""
    <div $ref="box"></div><slot />
    """
  end
end
