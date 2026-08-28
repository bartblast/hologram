# credo:disable-for-this-file Credo.Check.Readability.Specs
# A job type whose run/1 does whatever its outcome attribute names, so that one fixture covers
# every answer the runner has to classify and both halves of the authority rule. It declares
# allow :read and no allow :create, which is what makes a create under an acting user a denial
# rather than the teaching refusal a type declaring nothing gets.
defmodule Hologram.Test.Fixtures.Job.Module3 do
  use Hologram.Job

  alias Hologram.Auth
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Job.Module1

  attribute :outcome, :enum,
    values: [
      :create_next,
      :create_row,
      :error,
      :exit,
      :garbage,
      :ok,
      :ok_tuple,
      :raise,
      :record_actor,
      :record_order,
      :throw
    ]

  allow :read

  @impl Hologram.Job
  def run(%{outcome: :create_next}) do
    Hologram.Job.create!(Module1, [], trust: true)

    :ok
  end

  def run(%{outcome: :create_row}) do
    %{c: "by job"}
    |> Entity2.new()
    |> Hologram.DB.create!()

    :ok
  end

  def run(%{outcome: :error}), do: {:error, :smtp_down}

  def run(%{outcome: :exit}), do: exit(:boom)

  def run(%{outcome: :garbage}), do: nil

  def run(%{outcome: :ok}), do: :ok

  def run(%{outcome: :ok_tuple}), do: {:ok, :sent}

  def run(%{outcome: :raise}), do: raise("boom")

  def run(%{outcome: :record_actor}) do
    Process.put(:ran_as, Auth.user_id())

    :ok
  end

  def run(%{outcome: :record_order} = job) do
    Process.put(:ran_order, [job.id | Process.get(:ran_order, [])])

    :ok
  end

  def run(%{outcome: :throw}), do: throw(:boom)
end
