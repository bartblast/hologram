# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Model.Module2 do
  # A second entity type of fixed shape, for the claims about the entity type SET rather than
  # about one type's shape. Hand-written and marker-less for the same reason as
  # Hologram.Test.Fixtures.Model.Module1.

  def __attributes__ do
    [{:body, :string, [optional: true]}]
  end

  def __relationships__ do
    []
  end

  def __system_attributes__ do
    [{:created_at, :datetime, []}, {:id, :uuid, []}, {:updated_at, :datetime, []}]
  end
end
