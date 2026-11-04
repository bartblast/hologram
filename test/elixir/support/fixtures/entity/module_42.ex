# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module42 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module41

  attribute :caption, :string
  attribute :score, :integer

  relationship :note, Module41, optional: true
  relationship :origin, __MODULE__, optional: true

  derived :label, :string, fn caption -> caption <> "!" end

  derived :note_hidden, :boolean, fn note -> note.public == false end

  derived :rank, :enum, [values: [:high, :low]], fn score ->
    if score > 5, do: :high, else: :low
  end

  derived :shout, :string, fn label -> label <> "!" end

  allow :read, when: note_hidden == true
  allow :update, when: shout == "draft!!"
end
