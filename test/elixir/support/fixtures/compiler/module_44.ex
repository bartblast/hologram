# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module44 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.Module45

  def template do
    ~HOLO"""
    <Module45><p $ref="inside"></p></Module45>
    """
  end
end
