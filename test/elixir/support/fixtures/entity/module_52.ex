# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module52 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module1

  attribute :position, :integer, optional: true
  attribute :slug, :string

  relationship :workspace, Module1, optional: true

  unique [workspace, slug]
  unique [position, workspace]
end
