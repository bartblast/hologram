defmodule HologramFeatureTests.Entities.Reaction do
  use Hologram.Entity

  # One reaction per reactor and emoji: neither value is unique on its own, the pair is. The
  # allow lines are bare, so any visitor may write - what is under test is the key, not the
  # policies.
  attribute :emoji, :string
  attribute :reactor, :string

  unique [:reactor, :emoji]

  allow :create
  allow :read
  allow :update
end
