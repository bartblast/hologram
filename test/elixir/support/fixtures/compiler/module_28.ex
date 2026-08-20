# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module28 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.Module27

  def template do
    ~HOLO"""
    <Module27 a="1" b={@x} />
    <Module27 a="2"><Module27 b="3" /></Module27>
    """
  end
end
