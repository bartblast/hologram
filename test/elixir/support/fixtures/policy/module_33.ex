# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module33 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module34

  attribute :code, :string, server_only: true
  attribute :public, :boolean, default: false

  relationship :keys, [Module34], inverse: vault

  allow :read, when: public == true or none(key <- keys, key.name == code)
end
