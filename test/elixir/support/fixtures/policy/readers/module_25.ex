# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module25 do
  use Hologram.Entity

  attribute :keeper_id, :uuid, optional: true
  attribute :open, :boolean, default: false

  role :member

  allow :archive, when: keeper_id == user_id()
  allow :close, to: :member
  allow :delete, when: keeper_id != user_id()
  allow :update, when: open == true
end
