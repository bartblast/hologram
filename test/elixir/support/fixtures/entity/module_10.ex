# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module10 do
  use Hologram.Entity

  attribute :bio, :string, max_length: 10, optional: true
  attribute :count, :integer, min: 1, max: 10
  attribute :country_code, :string, length: 2, optional: true
  # The s modifier is here for what it makes Regex.opts/1 RETURN - [:dotall, {:newline,
  # :anycrlf}], whose second member is a tuple rather than a name. It changes nothing about
  # matching this pattern, which holds no dot.
  attribute :email, :string, format: ~r/@/s, optional: true
  attribute :handle, :string, min_length: 3, format: ~r/^[a-z_]+$/, optional: true
  attribute :held_at, :datetime, min: ~U[2026-01-01 00:00:00Z], optional: true
  attribute :percent, :integer, in: 0..100//5, optional: true
  attribute :priority, :integer, in: 1..5, optional: true
  attribute :rating, :float, min: 0, max: 5.0, optional: true
  attribute :released_on, :date, max: ~D[2030-12-31], optional: true
  attribute :username, :string, min_length: 3, max_length: 8, optional: true
end
