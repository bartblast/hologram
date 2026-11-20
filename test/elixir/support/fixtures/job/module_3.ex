# credo:disable-for-this-file Credo.Check.Readability.Specs
# A job type whose run/1 does whatever its outcome attribute names, so that one fixture covers
# every answer the runner has to classify and both halves of the authority rule. It declares
# allow :read and no allow :create, which is what makes a create under an acting user a denial
# rather than the teaching refusal a type declaring nothing gets.
defmodule Hologram.Test.Fixtures.Job.Module3 do
  use Hologram.Job

  alias Hologram.Auth
  alias Hologram.DB.EntityOperations
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Job.Module1

  attribute :outcome, :enum,
    values: [
      :create_next,
      :create_row,
      :delete_self,
      :error,
      :exit,
      :garbage,
      :ok,
      :ok_tuple,
      :raise,
      :record_actor,
      :swept,
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

  # Takes its own row away, so recording the outcome has no row to write to.
  def run(%{outcome: :delete_self} = job) do
    :ok = EntityOperations.delete(__MODULE__, job.id)

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

  # Fails its own row, standing for a sweep on another node that found the run's lock gone.
  def run(%{outcome: :swept} = job) do
    :ok = EntityOperations.update(__MODULE__, job.id, %{error: "swept", status: :failed})

    :ok
  end

  def run(%{outcome: :throw}), do: throw(:boom)
end
