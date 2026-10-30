# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module10 do
  use Hologram.Entity

  attribute :archived, :boolean, default: false

  role :editor

  allow :create
  allow :read
  allow :update, to: :editor, when: archived == false
end
