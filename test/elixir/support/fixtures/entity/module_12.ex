# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module12 do
  use Hologram.Entity

  role :admin, extends: [:editor, :owner]
  role :editor, extends: :viewer
  role :owner, extends: :editor
  role :viewer
end
