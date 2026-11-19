# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module37 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module36

  attribute :body, :string, optional: true

  relationship :channel, Module36

  allow :read
  allow :update, as: :moderate, via: {:archive, channel}
  allow :update, as: :edit, via: channel
end
