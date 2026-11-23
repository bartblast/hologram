defmodule HologramSyncBenchmark.Entities.SetTag do
  use Hologram.Entity

  alias HologramSyncBenchmark.Entities.SetPost

  attribute :hidden, :boolean, default: false
  attribute :name, :string

  relationship :posts, [SetPost], inverse: tags

  # Hiding the tag and showing it again is what makes every session drop it and be handed it back,
  # each scanning its whole set.
  allow :read, when: hidden == false
  allow :update
end
