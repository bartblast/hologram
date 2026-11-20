# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module30 do
  use Hologram.Entity

  role :editor
  role :owner

  allow :read, to: :owner
  allow :update, to: [:editor, :owner]
end
