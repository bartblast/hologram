# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module39 do
  use Hologram.Component

  prop :size, :list, values: [[:small], [:large]]

  def template do
    ~HOLO"Module39 template"
  end
end
