# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Benchmarks.Fixtures.Entity13 do
  @moduledoc false

  use Hologram.Entity

  attribute :label, :string

  allow :read
end
