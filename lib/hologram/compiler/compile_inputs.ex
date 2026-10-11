defmodule Hologram.Compiler.CompileInputs do
  @moduledoc """
  What a compile with nothing changed is decided by, recorded in the build dir when a compile
  finishes with every page built, so that the first compile in the next VM can tell before it loads
  anything that it has nothing to do (see `Mix.Tasks.Compile.Hologram`).

  For the modules: the Elixir compile manifest of every loaded application that has one, digested.
  The Elixir compiler rewrites an application's manifest whenever it compiles a module of it and
  leaves it alone otherwise. For the JavaScript a bundle inlines: every file and fingerprint pair
  the served bundles recorded for the files esbuild read (see `Hologram.Compiler.bundle/4`), so that
  a file two bundles read at different contents is recorded with both. For the rest of
  what a bundle is built from: the bundle inputs that need no module (see
  `Hologram.Compiler.build_bundle_inputs/1`), the client config and the files in the static dir.
  """

  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Compiler
  alias Hologram.Reflection

  # Bumped when the record's shape changes: a dump of another version is not loaded. An upgrade of
  # Hologram needs no bump, since it rewrites the :hologram application's manifest, which the record
  # holds.
  @dump_version 1

  @type t :: %{
          bundle_inputs: map,
          client_config: String.t(),
          js_inputs: [{String.t(), Compiler.js_input_fingerprint()}],
          manifests: [{atom, non_neg_integer}],
          static_files: [String.t()]
        }

  @doc """
  Builds the record of the world now, without the JavaScript inputs, which the caller takes from the
  bundles it served. Takes the compile task's options: `:assets_dir` and `:js_dir` for the bundle
  inputs, `:build_lib_dir` for the manifests and `:static_dir` for the files.
  """
  @spec build(keyword) :: %{
          bundle_inputs: map,
          client_config: String.t(),
          manifests: [{atom, non_neg_integer}],
          static_files: [String.t()]
        }
  def build(opts) do
    %{
      bundle_inputs: Compiler.build_bundle_inputs(opts),
      client_config: Compiler.client_config(),
      manifests: list_manifest_digests(opts[:build_lib_dir]),
      static_files: list_static_files(opts[:static_dir])
    }
  end

  @doc """
  Writes the record to the given path, atomically. The parent directory must exist.
  """
  @spec dump(t, String.t()) :: :ok
  def dump(record, path) do
    data = SerializationUtils.serialize({@dump_version, record})
    FileUtils.write_atomically!(path, data)
  end

  @doc """
  Reads the record at the given path, or returns nil when there is none or it is of another version.
  """
  @spec load(String.t()) :: t | nil
  def load(path) do
    with {:ok, data} <- File.read(path),
         {@dump_version, record} <- SerializationUtils.deserialize(data, true) do
      record
    else
      _no_record -> nil
    end
  end

  @doc """
  Whether the world is as the given record says: the manifests, the bundle inputs, the client config
  and the static files built again equal the recorded ones, and every recorded JavaScript file and
  fingerprint pair still holds (see `Hologram.Compiler.js_inputs_changed?/2`). A file recorded with
  two fingerprints, or as `:fresh`, always counts as changed.
  """
  @spec unchanged?(t, keyword) :: boolean
  def unchanged?(record, opts) do
    {js_inputs, rest} = Map.pop!(record, :js_inputs)

    js_fingerprints =
      js_inputs
      |> Enum.map(fn {path, _fingerprint} -> path end)
      |> Enum.uniq()
      |> Compiler.fingerprint_js_inputs(nil)

    rest == build(opts) and not Compiler.js_inputs_changed?(js_inputs, js_fingerprints)
  end

  # The Elixir compile manifest of every loaded application that has one, in application name order,
  # digested. Content rather than mtime: the compile task touches the umbrella apps' manifests after
  # every run (see refresh_umbrella_app_manifests/0 there).
  defp list_manifest_digests(build_lib_dir) do
    for app <- Enum.sort(Reflection.list_loaded_otp_apps()),
        path = Path.join([build_lib_dir, Atom.to_string(app), ".mix", "compile.elixir"]),
        {:ok, content} <- [File.read(path)] do
      {app, :erlang.phash2(content)}
    end
  end

  defp list_static_files(static_dir) do
    case File.ls(static_dir) do
      {:ok, file_names} -> Enum.sort(file_names)
      {:error, _reason} -> []
    end
  end
end
