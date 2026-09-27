defmodule HologramEcosystemTests.Ash.Item do
  use Ash.Resource,
    domain: HologramEcosystemTests.Ash.Domain,
    data_layer: Ash.DataLayer.Ets

  alias HologramEcosystemTests.Ash.Note
  alias HologramEcosystemTests.Ash.Types.Window

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    action :summarize, :string do
      argument :id, :uuid, allow_nil?: false

      run fn input, _context ->
        {:ok, "item #{input.arguments.id}"}
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :available_on, :date, public?: true
    attribute :price, :money, public?: true
    attribute :stamp, HologramEcosystemTests.Ash.Types.Stamp, public?: true
    attribute :title, :string, public?: true
    attribute :window, Window, public?: true
  end

  relationships do
    has_many :notes, Note, public?: true
  end

  calculations do
    calculate :label, :string, expr("item: " <> title), public?: true

    calculate :greeting, :string, expr("hello " <> ^arg(:name)) do
      argument :name, :string, allow_nil?: false
      public? true
    end
  end

  aggregates do
    count :note_count, :notes, public?: true
  end

  code_interface do
    define :archive, action: :destroy
    define :create
    define_calculation :greeting, args: [:name]
    define :get, action: :read, get_by: [:id]
    define :list, action: :read
    define :list_all, action: :read, namespace: Admin
    define :summarize, args: [:id]
    define :update
  end
end
