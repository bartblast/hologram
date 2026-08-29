defmodule HologramFeatureTests.Entities.Todo do
  use Hologram.Entity

  # Every attribute here is chosen for a path a client-side write has to exercise: title for a
  # refusal the browser can judge on its own, slug for one only the server can (uniqueness is a
  # question about other rows), votes for a counter a move can carry past its floor, and done for
  # an ordinary put. The four allow lines are bare, so any visitor may write - what is under test
  # is the write path, not the policies.
  attribute :done, :boolean, default: false
  attribute :slug, :string, optional: true, unique: true
  attribute :title, :string, min_length: 1
  attribute :votes, :integer, default: 0, min: 0

  allow :create
  allow :delete
  allow :read
  allow :update
end
