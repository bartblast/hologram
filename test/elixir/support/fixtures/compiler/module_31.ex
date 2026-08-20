# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module31 do
  use Hologram.Component

  prop :size, :atom, required: true
  prop :label, :string

  def template do
    ~HOLO"Module31 template"
  end
end
