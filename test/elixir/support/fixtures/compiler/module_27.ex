# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module27 do
  use Hologram.Component

  prop :a, :string
  prop :b, :string

  def template do
    ~HOLO"Module27 template"
  end
end
