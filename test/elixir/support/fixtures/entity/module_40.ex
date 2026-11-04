# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module40 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module34
  alias Hologram.Test.Fixtures.Entity.Module41

  attribute :name, :string

  relationship :mentors, [Module34]
  relationship :notes, [Module41], inverse: team

  derived :capped_note_count, :integer, fn notes ->
    notes
    |> take(2)
    |> count()
  end

  derived :mentor_message_count, :integer, fn mentors -> count(mentors.channel.messages) end

  derived :note_count, :integer, fn notes -> count(notes) end

  derived :note_tag_count, :integer, fn notes -> count(notes.tags) end

  allow :read
end
