# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Model.Module1 do
  # Implements the entity reflection contract by hand, reading each part of its shape from the
  # process dictionary, so a test can vary one part while the module name - itself part of the
  # hash - stays put. The entity marker is deliberately absent: Reflection must never discover
  # this module as part of the real data model.
  #
  # The policy and role functions raise, which is what proves they never feed the hash.

  @default_attributes [{:title, :string, []}]

  @default_system_attributes [
    {:created_at, :datetime, []},
    {:id, :uuid, []},
    {:updated_at, :datetime, []}
  ]

  def __attributes__ do
    Process.get({__MODULE__, :attributes}, @default_attributes)
  end

  def __policies__ do
    raise "__policies__/0 must not feed the model hash"
  end

  def __relationships__ do
    Process.get({__MODULE__, :relationships}, [])
  end

  def __roles__ do
    raise "__roles__/0 must not feed the model hash"
  end

  def __system_attributes__ do
    Process.get({__MODULE__, :system_attributes}, @default_system_attributes)
  end
end
