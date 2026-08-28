# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Shared.Module1 do
  use Hologram.Policy

  role :viewer

  allow :read, to: :viewer
end
