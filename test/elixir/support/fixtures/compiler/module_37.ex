# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module37 do
  use Hologram.Component

  prop :size, :atom, values: [:small, :large]
  prop :label, :string, values: ["abc", "xyz"]
  prop :free, :string

  def template do
    ~HOLO"Module37 template"
  end
end
