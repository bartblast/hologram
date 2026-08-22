# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Benchmarks.Fixtures.Entity16 do
  @moduledoc false

  use Hologram.Entity

  attribute :name, :string
  attribute :position, :integer

  allow :read
end
