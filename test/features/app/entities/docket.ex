defmodule HologramFeatureTests.Entities.Docket do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Sticker

  attribute :status, :string

  relationship :stickers, [Sticker]

  # The rule reads a field the same call can change, so closing a docket while sticking a sticker
  # on it passes only when the whole call is judged against the docket it started from.
  allow :read
  allow :update, when: status == "open"
end
