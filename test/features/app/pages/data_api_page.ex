defmodule HologramFeatureTests.DataApiPage do
  use Hologram.Page
  use Hologram.DB

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.WriteError
  alias HologramFeatureTests.Entities.Account
  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Entities.Review

  route "/data-api"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  # A button is clicked by a label the browser driver matches as a SUBSTRING, so no label
  # here may contain another's - a test clicking the shorter one would find both. That is
  # why the in-transaction buttons say "duplicate" where their top-level twins say
  # "duplicate account", and why the missing-product buttons avoid "Create review"
  # rather than extending it.
  def template do
    ~HOLO"""
    <p>
      <button $click={command: :create_duplicate_account}> Create duplicate account </button>
      <button $click={command: :create_duplicate_account_in_transaction}> Create duplicate in transaction </button>
      <button $click={command: :create_invalid_duplicate_account}> Create invalid duplicate account </button>
      <button $click={command: :create_invalid_review_for_missing_product}> Submit invalid review for a missing product </button>
      <button $click={command: :create_review}> Create review </button>
      <button $click={command: :create_review_for_missing_product}> Review a missing product </button>
      <button $click={command: :delete_referenced_product}> Delete referenced product </button>
      <button $click={command: :reject_invalid_review}> Reject invalid review </button>
      <button $click={command: :raise_on_duplicate_account}> Raise on duplicate account </button>
      <button $click={command: :raise_on_duplicate_account_in_transaction}> Raise on duplicate in transaction </button>
      <button $click={command: :run_query}> Run query </button>
      <button $click={command: :update_into_duplicate_account}> Update into duplicate account </button>
      <button $click={command: :validate_changes}> Validate changes </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:create_duplicate_account, _params, server) do
    %{handle: "taken"}
    |> Account.new()
    |> DB.create!()

    result =
      %{handle: "taken"}
      |> Account.new()
      |> DB.create()

    put_action(server, :show_result, result: "duplicate_account_#{inspect(result)}")
  end

  def command(:create_duplicate_account_in_transaction, _params, server) do
    %{handle: "taken"}
    |> Account.new()
    |> DB.create!()

    result =
      DB.transaction(fn ->
        refusal =
          %{handle: "taken"}
          |> Account.new()
          |> DB.create()

        other =
          %{handle: "other"}
          |> Account.new()
          |> DB.create!()

        {refusal, other.handle}
      end)

    put_action(server, :show_result,
      result: "duplicate_account_in_transaction_#{inspect(result)}"
    )
  end

  def command(:create_invalid_duplicate_account, _params, server) do
    %{handle: "taken"}
    |> Account.new()
    |> DB.create!()

    result =
      %{bio: "far too long for ten", handle: "taken"}
      |> Account.new()
      |> DB.create()

    put_action(server, :show_result, result: "invalid_duplicate_account_#{inspect(result)}")
  end

  def command(:create_invalid_review_for_missing_product, _params, server) do
    product =
      %{name: "invalid_missing_product"}
      |> Product.new()
      |> DB.create!()

    DB.delete!(Product, product.id)

    result =
      %{product_id: product.id, rating: 0}
      |> Review.new()
      |> DB.create()

    put_action(server, :show_result,
      result: "invalid_review_for_missing_product_#{inspect(result)}"
    )
  end

  def command(:create_review, _params, server) do
    product =
      %{name: "create_review_product"}
      |> Product.new()
      |> DB.create!()

    review =
      %{product_id: product.id, rating: 4}
      |> Review.new()
      |> DB.create!()

    persisted_review = DB.read(Review, review.id)

    put_action(server, :show_result, result: "created_review_#{persisted_review.rating}")
  end

  def command(:create_review_for_missing_product, _params, server) do
    product =
      %{name: "missing_product"}
      |> Product.new()
      |> DB.create!()

    DB.delete!(Product, product.id)

    result =
      %{product_id: product.id, rating: 4}
      |> Review.new()
      |> DB.create()

    put_action(server, :show_result, result: "review_for_missing_product_#{inspect(result)}")
  end

  def command(:delete_referenced_product, _params, server) do
    product =
      %{name: "referenced_product"}
      |> Product.new()
      |> DB.create!()

    %{product_id: product.id, rating: 3}
    |> Review.new()
    |> DB.create!()

    result = DB.delete(Product, product.id)

    put_action(server, :show_result, result: "deleted_referenced_#{inspect(result)}")
  end

  def command(:reject_invalid_review, _params, server) do
    product =
      %{name: "reject_invalid_review_product"}
      |> Product.new()
      |> DB.create!()

    result =
      try do
        %{product_id: product.id, rating: 0}
        |> Review.new()
        |> DB.create!()

        "rejected_nothing"
      rescue
        error in WriteError -> error.message
      end

    put_action(server, :show_result, result: result)
  end

  def command(:raise_on_duplicate_account, _params, server) do
    %{handle: "taken"}
    |> Account.new()
    |> DB.create!()

    result =
      try do
        %{handle: "taken"}
        |> Account.new()
        |> DB.create!()

        "raised_nothing"
      rescue
        error in WriteError -> error.message
      end

    put_action(server, :show_result, result: result)
  end

  def command(:raise_on_duplicate_account_in_transaction, _params, server) do
    %{handle: "taken"}
    |> Account.new()
    |> DB.create!()

    result =
      try do
        DB.transaction(fn ->
          %{handle: "taken"}
          |> Account.new()
          |> DB.create!()
        end)

        :raised_nothing
      rescue
        _error in WriteError -> :raised
      end

    put_action(server, :show_result,
      result: "raise_on_duplicate_account_in_transaction_#{inspect(result)}"
    )
  end

  def command(:run_query, _params, server) do
    Enum.each(["run_query_banana", "run_query_apple", "run_query_excluded"], fn name ->
      %{name: name}
      |> Product.new()
      |> DB.create!()
    end)

    names =
      Product
      |> filter(name: {:!=, "run_query_excluded"})
      |> order_by(:name)
      |> DB.read()
      |> Enum.map_join(",", & &1.name)

    put_action(server, :show_result, result: names)
  end

  def command(:update_into_duplicate_account, _params, server) do
    %{handle: "first"}
    |> Account.new()
    |> DB.create!()

    second =
      %{handle: "second"}
      |> Account.new()
      |> DB.create!()

    result = DB.update(Account, second.id, handle: "first")

    put_action(server, :show_result, result: "updated_into_duplicate_#{inspect(result)}")
  end

  def command(:validate_changes, _params, server) do
    validation_result = Entity.validate(Review, %{rating: 9})

    put_action(server, :show_result, result: "validated_#{inspect(validation_result)}")
  end
end
