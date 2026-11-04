# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module40 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module34
  alias Hologram.Test.Fixtures.Entity.Module39
  alias Hologram.Test.Fixtures.Entity.Module41

  attribute :name, :string

  relationship :mentors, [Module34]
  relationship :notes, [Module41], inverse: team
  relationship :players, [Module39]

  derived :capped_note_count, :integer, fn notes ->
    notes
    |> take(2)
    |> count()
  end

  derived :mentor_message_count, :integer, fn mentors -> count(mentors.channel.messages) end

  derived :named_tag_count, :integer, fn notes, name ->
    notes
    |> filter(any(tag <- tags, tag.c == ^name))
    |> count()
  end

  derived :no_note, Module41, fn -> nil end

  derived :note_count, :integer, fn notes -> count(notes) end

  derived :note_tag_count, :integer, fn notes -> count(notes.tags) end

  derived :picked_notes, [Module41], fn notes, name ->
    if name == "tagged", do: include(notes, tags), else: include(notes, team)
  end

  derived :second_note, Module41, fn notes ->
    notes
    |> skip(1)
    |> one()
  end

  allow :read
end
