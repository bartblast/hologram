# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module64 do
  use Hologram.Entity

  attribute :code, :string, server_only: true
  attribute :label, :string

  allow :read
  allow :update, only: [:label], when: code == "kestrel"
end
