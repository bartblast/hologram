# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module40 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.Module31

  def template do
    ~HOLO"Module40 template"
  end

  # A DOM-shaped tuple that no template renders - the compiler must not treat it as a usage.
  def dom_fixture do
    {:component, Module31, [], []}
  end
end
