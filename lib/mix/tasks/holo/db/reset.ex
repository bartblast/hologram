defmodule Mix.Tasks.Holo.Db.Reset do
  @shortdoc "Rebuilds the dev or test database's Hologram schema from nothing and runs the seeds"

  @moduledoc """
  Rebuilds the Hologram part of the dev or test database from nothing: its schema and its seed
  data.

      $ mix holo.db.reset
      $ MIX_ENV=test mix holo.db.reset

  A missing database is created. A present one loses Hologram's two schemas, hologram_data and
  hologram_system, with all their data, and nothing else, so the tables of an Ecto repo sharing
  the database stay. The schema is then built from the model, and the seeds file
  `app/seeds.exs` runs when the project has one.

  ## The test database

  Test runs never use the configured test database: each run gets a database of its own (see
  `Hologram.Test.setup/0`). The reset makes the configured one the database for a manual session
  in the test env, like `MIX_ENV=test HOLOGRAM_START=1 iex -S mix`. A test boot doesn't build the
  schema, so run the reset again after a model change, before the next such session.

  The test env reset also drops what earlier test runs left behind on the server, by name: the
  run databases of the configured database, the shadow databases the migration checks named
  after them, and the shared databases test runs used before each run got its own. It skips any
  database a session is connected to, or that a role the configured one can't act as owns, and a
  database whose shadow it skips, and says so.

  The task refuses, changing nothing:

    * in every env but dev and test,
    * while another client is connected to the database - stop the app and close psql first,
    * when the database belongs to another app or env, or its migrations build it,
    * when objects outside Hologram's schemas depend on them, since dropping the schemas would
      delete those objects too,
    * when the configured database name is longer than PostgreSQL's limit of 63 bytes,
    * when an earlier task in the same mix command, like one of an alias, compiled or started
      the app already - the reset runs in a command of its own.

  A seeds file that raises fails the task, with the schema already built. A boot that fails
  leaves the schemas dropped: fix what it names and run the task again.
  """

  use Mix.Task

  alias Hologram.DB
  alias Hologram.DB.Config
  alias Hologram.DB.Reset
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Entity.Model
  alias Hologram.Reflection

  @seeds_path "app/seeds.exs"

  @doc false
  @impl Mix.Task
  def run(_args) do
    env = Hologram.env()
    refuse_env!(env)

    refuse_started_app!()

    compile!()
    Mix.Task.run("app.config")

    # After the compile, which loads an umbrella's apps for the root to find its own among.
    otp_app = Reflection.otp_app()

    database_opts = resolve_database_opts!(env)
    reset(database_opts, otp_app, env)

    # After the reset, which guards the configured database first, so a refused one drops nothing.
    if env == :test do
      drop_leftovers(database_opts, otp_app)
      build_test_schema()
    end

    # Started after the drop, so the app's own pools don't count as other clients.
    Mix.Task.run("app.start")
    report_build(database_opts[:database])

    run_seeds(Path.join(Reflection.otp_app_dir(), @seeds_path))
  end

  @doc false
  # Runs the seeds file at the given path, when there is one. A seed that raises raises here,
  # with its own stacktrace. Evaluated rather than required, so the code server keeps no record
  # of it and running it again runs it again.
  @spec run_seeds(String.t()) :: :ok
  def run_seeds(path) do
    relative_path = Path.relative_to_cwd(path)

    if File.exists?(path) do
      Code.eval_file(path)
      print("Ran the seeds in #{relative_path}")
    else
      print("No seeds ran - there's no #{relative_path}")
    end
  end

  # A test boot doesn't reconcile, and sync's dispatcher reads the system tables as it starts, so
  # the schema is built before the app starts, through a pool of its own.
  defp build_test_schema do
    if Model.exists?() do
      {:ok, pid} = DB.start_link()

      try do
        DB.await_database()
        SchemaReconciler.reconcile(DB.reconciliation_context())
      after
        Supervisor.stop(pid)
      end
    end
  end

  # The query cache and the index plan read what the Hologram compile writes, which runs only
  # with the flag set, and the app's boot then starts the database, as under mix holo. Mix runs
  # a task once per command and answers :noop when it ran already, so a compile an earlier task
  # ran without the flag would leave the boot reading stale files.
  defp compile! do
    flag_was_set? = System.get_env("HOLOGRAM_START") == "1"
    System.put_env("HOLOGRAM_START", "1")

    if Mix.Task.run("compile") == :noop and not flag_was_set? do
      Mix.raise(
        "mix holo.db.reset runs in a mix command of its own - an earlier task in this one " <>
          "compiled the app without HOLOGRAM_START=1, so Hologram's compile step didn't run"
      )
    end
  end

  defp drop_leftovers(database_opts, otp_app) do
    leftovers = Reset.leftovers(otp_app, database_opts[:database])

    fn -> Reset.drop_leftovers!(database_opts, :test, leftovers) end
    |> raise_as_task_error()
    |> report_sweep(database_opts[:user])
  end

  defp print(output) do
    # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
    IO.puts(output)
  end

  # Only the reset's errors become a task error, while a seed's keeps its stacktrace.
  # Exception.message/1, since Postgrex.Error keeps its detail in :postgres.
  defp raise_as_task_error(fun) do
    fun.()
  rescue
    error in [Postgrex.Error, RuntimeError] ->
      error
      |> Exception.message()
      |> Mix.raise()
  end

  defp refuse_env!(env) when env in [:dev, :test], do: :ok

  defp refuse_env!(env) do
    Mix.raise(
      "mix holo.db.reset runs in the dev and test envs only - the current env is #{inspect(env)}"
    )
  end

  # Mix runs app.start once per command too, so an app an earlier task started would keep
  # running, its connections counting as other clients, and no boot would build the schema. The
  # check looks for Hologram, which the app starts first, since an umbrella root can't name its
  # app before the compile, and it comes before the start flag is set, so a refusal in a running
  # app's IEx session leaves Hologram there as it was.
  defp refuse_started_app! do
    if List.keymember?(Application.started_applications(), :hologram, 0) do
      Mix.raise(
        "mix holo.db.reset runs in a mix command of its own - an earlier task in this one " <>
          "started the app already, and the reset has to run before the app starts"
      )
    end
  end

  defp report_build(database) do
    if Model.exists?() do
      print(~s(Built the Hologram schema of database "#{database}"))
    else
      print("The app declares no entities - no Hologram schema to build")
    end
  end

  defp report_reset(:created, database), do: print(~s(Created database "#{database}"))

  defp report_reset(:dropped, database) do
    print(~s(Dropped the Hologram schemas of database "#{database}"))
  end

  defp report_reset(:empty, database) do
    print(~s(Database "#{database}" has no Hologram schemas - nothing to drop))
  end

  defp report_sweep(%{dropped: dropped, skipped: skipped}, user) do
    Enum.each(dropped, &print(~s(Dropped leftover test database "#{&1}")))

    Enum.each(skipped, fn
      {database, :in_use} ->
        print(~s(Skipped leftover test database "#{database}" - a session is connected to it))

      {database, :not_owner} ->
        print(
          ~s(Skipped leftover test database "#{database}" - user "#{user}" can't drop it, ) <>
            "since another role owns it"
        )

      {database, :shadow_kept} ->
        print(
          ~s(Skipped leftover test database "#{database}" - its shadow database was skipped, ) <>
            "and a later reset finds the shadow through it"
        )
    end)
  end

  defp reset(database_opts, otp_app, env) do
    fn -> Reset.reset!(database_opts, otp_app, env) end
    |> raise_as_task_error()
    |> report_reset(database_opts[:database])
  end

  # A config the resolve can't complete is the user's to fix, so it's a task error too.
  defp resolve_database_opts!(env) do
    :hologram
    |> Application.get_env(:database, [])
    |> Config.resolve!(env)
  rescue
    error in ArgumentError ->
      error
      |> Exception.message()
      |> Mix.raise()
  end
end
