# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module39 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module34

  attribute :kind, :enum, values: [:guest, :staff]
  attribute :score, :integer

  relationship :member, Module34, optional: true
  relationship :mentors, [Module34]

  derived :gold, :boolean, fn tier -> tier == :gold end

  derived :kind_label, :enum, [values: [:guest, :staff]], fn kind -> kind end

  derived :member_name, :string, fn member -> member.display_name end

  derived :ratio, :float, fn score -> score end

  derived :tier, :enum, [values: [:gold, :silver, :bronze]], fn score ->
    if score > 10, do: :gold, else: if(score > 5, do: :silver, else: :bronze)
  end

  allow :read
end
