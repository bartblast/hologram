defmodule Hologram.Job do
  @moduledoc """
  The behaviour and construct for a job - work that runs after the transaction that enqueued it
  commits, and runs again if it fails, up to a limit.

  A job is data: it declares what it needs the way an entity type does, it has a table, it
  shows up in migrations, and it can be queried like any type - which is what lets an app list
  what is pending, see what failed, and rename a job without losing what was already queued.
  What it adds is `run/1`, which a worker calls with the job once its row has committed:

      defmodule MyApp.Jobs.NotifyMembers do
        use Hologram.Job

        alias MyApp.Project

        attribute :reason, :enum, values: [:created, :archived]

        relationship :project, Project

        allow :create, via: project
        allow :read, when: actor_id == user_id()

        @impl Hologram.Job
        def run(%{project_id: project_id, reason: reason}) do
          ...
          :ok
        end
      end

  The job is enqueued wherever the write it belongs to happens - in an action, a command, a
  seed - and rides in that write's transaction:

      Job.create!(MyApp.Jobs.NotifyMembers, project_id: project.id, reason: :archived)

  Refuse the transaction and the job never existed, so nothing runs. Let it commit and the job
  runs, as the user who enqueued it.

  A job that fails is tried again, up to 10 attempts unless its use line gives another number,
  written out:

      use Hologram.Job, max_attempts: 3

  A run fails by answering `{:error, reason}`, by raising, throwing or exiting, or by being cut
  short before its outcome is recorded - the node stopping, the run crashing or being killed, its
  lock connection to the database being lost, the outcome write failing. A worker sweeping for runs
  cut short counts them as failed attempts, with an error saying so.

  The wait before the next attempt starts at about 30 seconds and grows fourfold each time, up to
  about 6 hours, so the default 10 attempts span about a day. Meanwhile the job is `:queued`, with
  its `attempt` and the last `error` on its row. A job out of attempts ends `:failed`, keeping the
  error, and stays there to be inspected.

  So a job can run more than once, and a run cut short may have done all, part or none of its
  work: run/1 has to be safe to repeat. A job that must never run twice sets `max_attempts: 1`.

  The attempt limit is checked when an attempt fails, so a job already waiting for a retry when
  the limit is lowered still gets that run. To stop the ones past the new limit at once, delete
  them as part of the deploy. For a new limit of 3 they are `status == :queued and attempt >= 3`.

  A run that doesn't end within its time limit is killed and counts as a failed attempt, so a run
  that never returns can't keep its row running or hold on to its slot. The limit is 1 hour unless
  the use line gives another, in milliseconds, written out:

      use Hologram.Job, timeout: 60_000

  It covers the whole run, including claiming the job and recording its outcome. A run killed
  before its claim committed hasn't started, so it isn't counted and the job is tried again, which
  means a limit shorter than the claim never runs the job. The limit can't be turned off: a job
  that needs longer sets a bigger number.

  A kill can't interrupt native code. A run stuck in a regular NIF keeps its row, slot and lock
  until the call returns. One stuck in a dirty NIF, like file I/O on a dead network mount, is let
  go at once while the call carries on, so it can overlap the job's next attempt, and each such
  call holds a VM thread until it returns. Give file I/O and native calls in run/1 timeouts of
  their own.

  Attributes and relationships are what a job carries, so they are declared and typed rather
  than passed as a payload: a declaration is what a policy can name and what a migration can
  move forward.

  Every job also carries what the framework records about it, readable like any attribute and the
  framework's alone to write: `status`, `attempt` (how many runs have started), `scheduled_at`
  (when it is next due), `error` (server-only) and `actor_id`. The names are taken, so a job type
  can't declare its own attribute under one of them.

  Each node runs up to 10 jobs of a type at once. A job type that should run fewer at once, or
  more, says so in its use line, with the number written out:

      use Hologram.Job, max_concurrency: 2

  The limit is per node and per job type, so a type running at its limit doesn't stop other types
  from starting theirs.
  """

  alias Hologram.Auth.Context
  alias Hologram.DB
  alias Hologram.DB.Writer
  alias Hologram.Entity
  alias Hologram.Entity.Validator
  alias Hologram.MisuseError
  alias Hologram.Policy
  alias Hologram.Query
  alias Hologram.Reflection
  alias Hologram.WriteError

  # How many jobs of a type a node runs at once unless the type sets its own limit. A fixed number
  # rather than one worked out from the node, so the database connections the runs take can be
  # counted per node.
  @default_max_concurrency 10

  # How many times a job runs before it is left failed unless the type sets its own limit. With the
  # wait between attempts (see Hologram.Job.Runner.retry_delay_ms/1) it spans about a day, so a job
  # outlasts an outage until someone can fix its cause.
  @default_max_attempts 10

  # How long a run may take unless the type sets its own limit. Generous, because killing a run that
  # was still working is worse than a stuck one holding a slot for a while: the run is repeated.
  @default_timeout :timer.hours(1)

  @doc """
  Runs the job.

  Called by a worker with the job as it was read from its row, after the row committed, once per
  attempt, with the acting user set to whoever enqueued it - so reads are filtered and writes are
  evaluated as that user's. Returns :ok when the work is done, or {:error, reason} when it
  failed. Raising fails the attempt with the exception. A failed attempt is tried again until the
  job is out of attempts, so this has to be safe to run more than once.
  """
  @callback run(job :: Entity.t()) :: :ok | {:error, any}

  defmacro __using__(opts) do
    Validator.validate_use_job_opts!(__CALLER__.module, opts)

    max_attempts = Keyword.get(opts, :max_attempts, @default_max_attempts)
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    quote do
      use Hologram.Entity

      @behaviour Hologram.Job

      @before_compile Hologram.Job

      # The attributes every job carries and only the framework sets, declared as ordinary
      # attributes so that storage, the mapping, migrations, revisions, the wire and policies
      # treat them as they treat any attribute - and guarded from being set by anything else:
      # Entity.new/2 refuses them, the wire refuses them from a client, and the enqueue stamps
      # the actor from the ambient context and the due time from the node's clock.
      attribute :actor_id, :uuid, optional: true
      attribute :attempt, :integer, default: 0
      attribute :error, :string, optional: true, server_only: true
      attribute :scheduled_at, :datetime, optional: true
      attribute :status, :enum, values: [:queued, :running, :done, :failed], default: :queued

      @doc """
      Returns true to indicate that the callee module is a job type module (has "use Hologram.Job" directive).

      ## Examples

          iex> __is_hologram_job__()
          true
      """
      @spec __is_hologram_job__() :: boolean
      def __is_hologram_job__, do: true

      @doc """
      Returns how many times a job of this type runs before it is left failed.

      ## Examples

          iex> __job_max_attempts__()
          10
      """
      @spec __job_max_attempts__() :: pos_integer
      def __job_max_attempts__, do: unquote(max_attempts)

      @doc """
      Returns how many jobs of this type a node runs at once.

      ## Examples

          iex> __job_max_concurrency__()
          10
      """
      @spec __job_max_concurrency__() :: pos_integer
      def __job_max_concurrency__, do: unquote(max_concurrency)

      @doc """
      Returns how long a run of a job of this type may take, in milliseconds.

      ## Examples

          iex> __job_timeout__()
          3600000
      """
      @spec __job_timeout__() :: pos_integer
      def __job_timeout__, do: unquote(timeout)
    end
  end

  # The behaviour's own "not implemented" warning says the same thing, but a warning is not an
  # error outside a build that makes it one - and a job with nothing to run would fail at its
  # first run rather than at the line that forgot it.
  @doc false
  defmacro __before_compile__(env) do
    if not Module.defines?(env.module, {:run, 1}, :def) do
      raise Hologram.CompileError,
        message:
          "#{inspect(env.module)} uses Hologram.Job but defines no run/1 - run/1 is the work a job does, run after its row commits"
    end
  end

  @doc """
  Creates a job of the given job type from the given values (a map or a keyword list), enqueuing it.

  The job is written as a row of its type, in whatever transaction the caller is already in, with
  its status queued and its actor the acting user - nobody, on the trusted tier, and nobody for a
  trust claim made under a user id no user entity can have, like an app's own serial id. It runs
  after that transaction commits: a worker calls the job type's run/1 with the job, under the
  acting user's authority, and records the outcome on it. A run that fails or is cut short is tried
  again, up to the job type's max_attempts/1. A transaction that rolls back leaves no job, so
  nothing runs.

  Returns {:ok, job} with the written job, or {:error, violations} naming each attribute or
  reference that broke its declaration - the same answers, and the same checks, as writing any
  other row.

  In a session, signed in or not, the write is evaluated for :create. The :trust option claims the
  server's own authority instead, which is what a webhook, a seed or a job enqueuing another job
  does. It is the only option.

  Raises Hologram.MisuseError for a module that is not a job type, for an unknown option, and for a
  value of an attribute the framework sets. Raises Hologram.AccessDeniedError in a session when
  the job type declares no allow lines, since no rule can then grant the write, and when the
  acting user id is one no user entity can have, unless the call claims trust: true - such a job
  would run with no user, skipping every rule.
  """
  @spec create(module, %{optional(atom) => any} | keyword, keyword) ::
          {:ok, Entity.t()} | {:error, %{atom => list(atom | {atom, any})}}
  def create(job_type, values \\ %{}, opts \\ []) do
    job_type
    |> build(values, opts)
    |> Writer.create()
  end

  @doc """
  Like create/3, returning the written job directly and raising Hologram.WriteError instead of returning {:error, ...}.

  The spelling for a call site where a refused job is a reason to stop rather than something to
  answer.
  """
  @spec create!(module, %{optional(atom) => any} | keyword, keyword) :: Entity.t()
  def create!(job_type, values \\ %{}, opts \\ []) do
    job = build(job_type, values, opts)

    case Writer.create(job) do
      {:ok, written_job} ->
        written_job

      {:error, violations} ->
        raise WriteError,
          message:
            "cannot create #{inspect(job_type)}:\n" <>
              DB.refusal_lines(job_type, violations, Map.from_struct(job)),
          reason: violations
    end
  end

  @doc """
  Returns how many times a job of the given job type runs before it is left failed: the
  `:max_attempts` its use line gives, 10 by default.
  """
  @spec max_attempts(module) :: pos_integer
  def max_attempts(job_type), do: job_type.__job_max_attempts__()

  @doc """
  Returns how many jobs of the given job type a node runs at once: the `:max_concurrency` its use
  line gives, 10 by default.
  """
  @spec max_concurrency(module) :: pos_integer
  def max_concurrency(job_type), do: job_type.__job_max_concurrency__()

  @doc """
  Returns how long a run of a job of the given job type may take, in milliseconds, before it is
  killed and counted as a failed attempt: the `:timeout` its use line gives, 1 hour by default.
  """
  @spec timeout(module) :: pos_integer
  def timeout(job_type), do: job_type.__job_timeout__()

  @doc """
  Returns the names of the attributes every job type carries and only the framework sets, sorted: the acting user at the enqueue, how many runs have started, the failure record, when the job is next due, and the status.
  """
  @spec framework_attribute_names() :: list(atom)
  def framework_attribute_names, do: [:actor_id, :attempt, :error, :scheduled_at, :status]

  defp apply_claim(job, :none), do: job

  defp apply_claim(job, :trust), do: Query.trust(job)

  # The job the enqueue writes: constructed the way any entity is, then carrying whatever authority
  # the call claimed. Built here rather than in each verb so that the bang has the job in hand and
  # can name the values a refusal objected to.
  defp build(job_type, values, opts) do
    validate_job_type!(job_type)

    claim = parse_claim!(opts)

    validate_creatable!(job_type, claim)

    job_type
    |> Entity.new(values)
    |> apply_claim(claim)
  end

  # A literal option this refuses is a COMPILE warning as well as this raise: the clauses cover the
  # valid shapes and anything else raises, which the type checker reads as a call site passing what
  # the function does not take. The raise is what answers options built at run time.
  defp parse_claim!([]), do: :none

  defp parse_claim!(trust: true), do: :trust

  defp parse_claim!(opts) do
    raise MisuseError,
      message: "Job.create takes trust: true as its only option, got: #{inspect(opts)}"
  end

  # A job type declaring nothing is server-side work: no rule grants its create, so a session
  # cannot enqueue it and would otherwise be told they lack a permission, when the state is that
  # no permission exists. Claiming the server's authority is how one is enqueued under an actor,
  # so a trust claim skips the check rather than meeting it.
  defp validate_creatable!(job_type, claim) do
    if claim != :trust and Context.session?() and
         Policy.dead_entity_types([job_type]) != [] do
      raise Hologram.AccessDeniedError,
        message:
          "cannot create #{inspect(job_type)} as a user - it declares no allow lines, so no rule can grant the create. Add \"allow :create, ...\" to enqueue it from an action, or create it from server code, where there is no acting user."
    end

    :ok
  end

  defp validate_job_type!(job_type) do
    if not Reflection.job?(job_type) do
      raise MisuseError,
        message:
          "#{inspect(job_type)} is not a job type - Job.create takes a module defined with use Hologram.Job"
    end

    :ok
  end
end
