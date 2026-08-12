# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module15 do
  use Hologram.Entity

  attribute :label, :string, optional: true
  attribute :secret_note, :string, optional: true, server_only: true
  attribute :token, :string, server_only: true

  allow :read
end
