# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module41 do
  use Hologram.Component

  prop :ref, :any

  def template do
    ~HOLO"""
    <input $ref="search" />
    <li $ref={:message, 42}></li>
    <li $ref={{:comment, 7}}></li>
    <div $ref={@ref}></div>
    <{"span"} $ref="label" />
    """
  end
end
