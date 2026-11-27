# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module54 do
  use Hologram.Entity

  attribute :count, :integer, default: 0
  attribute :n1, :integer, optional: true
  attribute :n2, :integer, optional: true
  attribute :n3, :integer, optional: true
  attribute :n4, :integer, optional: true
  attribute :name, :string, optional: true
  attribute :s1, :string, optional: true
  attribute :s2, :string, optional: true
  attribute :s3, :string, optional: true
  attribute :s4, :string, optional: true
  attribute :s5, :string, optional: true
  attribute :s6, :string, optional: true
  attribute :u, :uuid, optional: true

  unique [name, count]
  unique [s1, n1, s2, n2, s3, n3, s4, n4, u]
  unique [s5, n1, s6, n2, n3]
end
