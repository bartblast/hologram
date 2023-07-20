# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module1 do
  use Hologram.Page

  def action(:action_1, _params, state), do: state
end
