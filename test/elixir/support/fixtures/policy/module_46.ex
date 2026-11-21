# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module46 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module56

  attribute :archived, :boolean, default: false
  attribute :open, :boolean, default: true

  relationship :site, Module56, optional: true

  role :editor
  role :member
  role :owner

  allow :read, to: [:member, :owner]
  allow :update, to: [:editor, :owner]
end
