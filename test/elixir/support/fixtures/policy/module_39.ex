# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module39 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module38

  attribute :body, :string, optional: true

  relationship :channel, Module38

  allow :read
  allow :update, via: {:update, channel}
end
