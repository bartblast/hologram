defmodule Hologram.Job do
  @moduledoc """
  The behaviour and construct for a job - work that runs once, after the transaction that
  enqueued it commits.

  A job is data: it declares what it needs the way an entity type does, it has a table, it
  shows up in migrations, and it can be queried like any type - which is what lets an app list
  what is pending, see what failed, and rename a job without losing what was already queued.
  What it adds is `run/1`, which a worker calls with the job once its row has committed:

      defmodule MyApp.Jobs.NotifyMembers do
        use Hologram.Job

        alias MyApp.Project

        attribute :reason, :enum, values: [:created, :archived]

        relationship :project, Project

        allow :create, via: :project
        allow :read, actor_id: user_id()

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
  runs once, as the user who enqueued it.

  Attributes and relationships are what a job carries, so they are declared and typed rather
  than passed as a payload: a declaration is what a policy can name and what a migration can
  move forward.
  """

  alias Hologram.Auth.Context
  alias Hologram.DB
  alias Hologram.DB.Writer
  alias Hologram.Entity
  alias Hologram.Entity.Validator
  alias Hologram.Policy
  alias Hologram.Query
  alias Hologram.Reflection
  alias Hologram.WriteError

  @doc """
  Runs the job.

  Called once by a worker with the job as it was read from its row, after the row committed,
  with the acting user set to whoever enqueued it - so reads are filtered and writes are
  evaluated as that user's. Returns :ok when the work is done, or {:error, reason} when it
  failed. Raising fails the job with the exception.
  """
  @callback run(job :: struct) :: :ok | {:error, any}

  defmacro __using__(opts) do
    Validator.validate_use_job_opts!(__CALLER__.module, opts)

    quote do
      use Hologram.Entity

      @behaviour Hologram.Job

      @before_compile Hologram.Job

      # The three attributes every job carries and only the framework sets, declared as ordinary
      # attributes so that storage, the mapping, migrations, revisions, the wire and policies
      # treat them as they treat any attribute - and guarded from being set by anything else:
      # Entity.new/2 refuses them, the wire refuses them from a client, and the enqueue stamps
      # the actor from the ambient context.
      attribute :actor_id, :uuid, optional: true
      attribute :error, :string, optional: true, server_only: true
      attribute :status, :enum, values: [:queued, :running, :done, :failed], default: :queued

      @doc """
      Returns true to indicate that the callee module is a job type module (has "use Hologram.Job" directive).

      ## Examples

          iex> __is_hologram_job__()
          true
      """
      @spec __is_hologram_job__() :: boolean
      def __is_hologram_job__, do: true
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
          "#{inspect(env.module)} uses Hologram.Job but defines no run/1 - run/1 is the work a job does, run once after its row commits"
    end
  end

  @doc """
  Creates a job of the given job type from the given values (a map or a keyword list), enqueuing it.

  The job is written as a row of its type, in whatever transaction the caller is already in, with
  its status queued and its actor the acting user - nobody, on the trusted tier. It runs once,
  after that transaction commits: a worker calls the job type's run/1 with the job, under the
  acting user's authority, and records the outcome on it. A transaction that rolls back leaves no
  job, so nothing runs.

  Returns {:ok, job} with the written job, or {:error, violations} naming each attribute or
  reference that broke its declaration - the same answers, and the same checks, as writing any
  other row.

  With an acting user set, the write is evaluated for :create, or for the operation named by the
  :authorize option. The :trust option claims the server's own authority instead, which is what a
  webhook, a seed or a job enqueuing another job does. The two are the only options, and asking
  for both raises.

  Raises ArgumentError for a module that is not a job type, for an unknown option, and for a value
  of an attribute the framework sets. Raises Hologram.AccessDeniedError when a user is acting and
  the job type declares no allow lines, since no rule can then grant the write.
  """
  @spec create(module, %{optional(atom) => any} | keyword, keyword) ::
          {:ok, struct} | {:error, %{atom => list(atom | {atom, any})}}
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
  @spec create!(module, %{optional(atom) => any} | keyword, keyword) :: struct
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
  Returns the names of the attributes every job type carries and only the framework sets, sorted: the acting user at the enqueue, the failure record, and the status.
  """
  @spec framework_attribute_names() :: list(atom)
  def framework_attribute_names, do: [:actor_id, :error, :status]

  defp apply_claim(job, :none), do: job

  defp apply_claim(job, {:authorize, operation}), do: Query.authorize(job, operation)

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

  defp parse_claim!(authorize: operation) when is_atom(operation), do: {:authorize, operation}

  defp parse_claim!(trust: true), do: :trust

  defp parse_claim!(opts) do
    raise ArgumentError,
      message: "Job.create takes authorize: operation or trust: true, got: #{inspect(opts)}"
  end

  # A job type declaring nothing is server-side work: no rule grants its create, so a user acting
  # cannot enqueue it and would otherwise be told they lack a permission, when the state is that
  # no permission exists. Claiming the server's authority is how one is enqueued under an actor,
  # so a trust claim skips the check rather than meeting it.
  defp validate_creatable!(job_type, claim) do
    if claim != :trust and Context.actor_user_id() != nil and
         Policy.dead_entity_types([job_type]) != [] do
      raise Hologram.AccessDeniedError,
        message:
          "cannot create #{inspect(job_type)} as a user - it declares no allow lines, so no rule can grant the create. Add \"allow :create, ...\" to enqueue it from an action, or create it from server code, where there is no acting user."
    end

    :ok
  end

  defp validate_job_type!(job_type) do
    if not Reflection.job?(job_type) do
      raise ArgumentError,
        message:
          "#{inspect(job_type)} is not a job type - Job.create takes a module defined with use Hologram.Job"
    end

    :ok
  end
end
