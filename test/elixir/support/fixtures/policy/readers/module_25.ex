# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module25 do
  use Hologram.Entity

  attribute :keeper_id, :id, optional: true
  attribute :open, :boolean, default: false

  role :member

  allow :delete, when: keeper_id != user_id()
  allow :update, when: open == true
  allow :update, as: :archive, only: [open], when: keeper_id == user_id()
  allow :update, as: :close, only: [keeper_id], to: :member
end
