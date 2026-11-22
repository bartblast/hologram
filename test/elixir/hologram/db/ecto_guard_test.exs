defmodule Hologram.DB.EctoGuardTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.EctoGuard

  alias Ecto.Adapters.SQL.Sandbox
  alias Hologram.Test.EctoRepo

  @moduletag :database

  describe "open_transaction_repo/1" do
    test "is nil when Ecto's registry isn't running" do
      refute open_transaction_repo(:hologram_test_no_such_registry)
    end

    test "is nil with a running repo and no transaction" do
      EctoRepo.start_for_test!()

      refute open_transaction_repo()
    end

    test "returns the repo inside its transaction" do
      EctoRepo.start_for_test!()

      assert EctoRepo.transaction(fn -> open_transaction_repo() end) == {:ok, EctoRepo}
    end

    test "is nil once the transaction has ended" do
      EctoRepo.start_for_test!()

      {:ok, :done} = EctoRepo.transaction(fn -> :done end)

      refute open_transaction_repo()
    end

    test "doesn't count the transaction Ecto's SQL sandbox holds for a test" do
      pid = EctoRepo.start_for_test!()
      :ok = Sandbox.checkout(pid)

      refute open_transaction_repo()
    end

    test "counts a transaction the code opens under Ecto's SQL sandbox" do
      pid = EctoRepo.start_for_test!()
      :ok = Sandbox.checkout(pid)

      assert EctoRepo.transaction(fn -> open_transaction_repo() end) == {:ok, EctoRepo}
    end

    test "keeps working for a repo whose module a code reload removed" do
      module = __MODULE__.RemovedRepo

      Module.create(
        module,
        quote do
          use Ecto.Repo, otp_app: :hologram, adapter: Ecto.Adapters.Postgres
        end,
        Macro.Env.location(__ENV__)
      )

      # Purged only here: a purge inside the transaction would kill the process running it.
      on_exit(fn ->
        :code.purge(module)
        :code.delete(module)
        :code.purge(module)
      end)

      EctoRepo.start_for_test!(repo: module)

      assert module.transaction(fn ->
               :code.delete(module)
               open_transaction_repo()
             end) == {:ok, module}

      refute open_transaction_repo()
    end

    test "sees a dynamic repo's transaction after the process switched to another repo" do
      other = EctoRepo.start_for_test!()
      repo = EctoRepo.start_for_test!()

      assert {:ok, EctoRepo} =
               EctoRepo.transaction(fn ->
                 EctoRepo.put_dynamic_repo(other)
                 result = open_transaction_repo()
                 EctoRepo.put_dynamic_repo(repo)

                 result
               end)
    end
  end
end
