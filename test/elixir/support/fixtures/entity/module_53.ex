# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module53 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module1

  attribute :a, :string, optional: true
  attribute :b, :string, optional: true
  attribute :c, :string, optional: true
  attribute :d, :string, optional: true
  attribute :e, :string, optional: true
  attribute :f, :string, optional: true
  attribute :kind, :enum, values: [:x, :y], optional: true
  attribute :slug, :string, optional: true, unique: true
  attribute :title, :string, optional: true

  relationship :owner, Module1, optional: true

  unique [:a, :b]
  unique [:b, :d]
  unique [:c, :kind, :owner]
  unique [:d, :e, :f]
  unique [:kind, :slug]

  allow :read
end
