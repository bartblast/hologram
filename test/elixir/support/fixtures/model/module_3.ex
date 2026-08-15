# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Model.Module3 do
  # An entity type whose attribute option holds a regex, built fresh on every call the way a
  # compiled entity type reports one: a regex read from a module attribute carries a compiled
  # pattern that differs from read to read, so two reads of the same declaration are not the
  # same term. Hand-written and marker-less for the same reason as
  # Hologram.Test.Fixtures.Model.Module1.

  def __attributes__ do
    source = Process.get({__MODULE__, :regex_source}, "@")

    [{:email, :string, [format: Regex.compile!(source)]}]
  end

  def __relationships__ do
    []
  end

  def __system_attributes__ do
    [{:created_at, :datetime, []}, {:id, :uuid, []}, {:updated_at, :datetime, []}]
  end
end
