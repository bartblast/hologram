# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module47 do
  use Hologram.Component

  def template do
    ~HOLO"""
    <b $ref={:nil_key, nil}></b><b $ref={:float_key, 1.5}></b>
    """
  end
end
