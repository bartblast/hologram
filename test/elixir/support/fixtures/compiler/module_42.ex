# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module42 do
  use Hologram.Component

  prop :open?, :boolean
  prop :shown?, :boolean

  def template do
    ~HOLO"""
    {%if @open?}<p $ref="toggle"></p>{%else}<div $ref="toggle"></div>{/if}
    {%if @shown?}<p $ref="hint"></p>{/if}
    """
  end
end
