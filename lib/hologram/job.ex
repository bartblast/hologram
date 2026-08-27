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

      Job.enqueue!(MyApp.Jobs.NotifyMembers, project_id: project.id, reason: :archived)

  Refuse the transaction and the job never existed, so nothing runs. Let it commit and the job
  runs once, as the user who enqueued it.

  Attributes and relationships are what a job carries, so they are declared and typed rather
  than passed as a payload: a declaration is what a policy can name and what a migration can
  move forward.
  """

  alias Hologram.Entity.Validator

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
  Returns the names of the attributes every job type carries and only the framework sets, sorted: the acting user at the enqueue, the failure record, and the status.
  """
  @spec framework_attribute_names() :: list(atom)
  def framework_attribute_names, do: [:actor_id, :error, :status]
end
