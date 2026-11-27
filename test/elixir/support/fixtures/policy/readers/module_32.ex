# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module32 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module30
  alias Hologram.Test.Fixtures.Policy.Readers.Module31
  alias Hologram.Test.Fixtures.Policy.Readers.Module33

  attribute :label, :string, optional: true

  relationship :bench, Module31, optional: true
  relationship :pegs, [Module33], inverse: tool
  relationship :workshop, Module30, optional: true

  allow :read

  # Each line holds a deciding none beside what it reads through the workshop, so the server sends
  # its verdict: a delegation to the workshop's update, and a role held on the bench's workshop.
  allow :delete, via: {:update, workshop}, when: none(peg <- pegs, peg.loose == true)

  allow :update,
    only: [label],
    to: {:editor, bench.workshop},
    when: none(peg <- pegs, peg.loose == true)
end
