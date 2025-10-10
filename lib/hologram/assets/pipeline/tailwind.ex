defmodule Hologram.Assets.Pipeline.Tailwind do
  @moduledoc false

  @doc """
  Bundles a Tailwind CSS asset.

  ## Parameters

    * `asset` - A map containing at least the `:source_path` key pointing to the CSS source file
    * `context` - A map containing `:assets_dir` and `:css_dist_dir` keys for output configuration

  ## Returns

  The asset map with an added `:bundle_path` key pointing to the bundled CSS file.
  """
  @spec bundle(map, map) :: map
  def bundle(asset, context) do
    basename = Path.basename(asset.source_path, ".css")
    bundle_path = Path.join(context.css_dist_dir, "#{basename}.css")

    args = [
      "--input=#{asset.source_path}",
      "--output=#{bundle_path}"
    ]

    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    profile = String.to_atom(basename)
    previous_profile_config = Application.get_env(:tailwind, profile)

    Application.put_env(:tailwind, profile,
      args: args,
      cd: Path.dirname(context.assets_dir)
    )

    try do
      # If Tailwind is not installed, the project will fail to compile
      # when the Tailwind module is explicitly called.
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Tailwind, :install_and_run, [profile, []])
    after
      if previous_profile_config do
        Application.put_env(:tailwind, profile, previous_profile_config)
      else
        Application.delete_env(:tailwind, profile)
      end
    end

    Map.put(asset, :bundle_path, bundle_path)
  end

  @doc """
  Checks if Tailwind is installed and available.

  Attempts to load the Tailwind module to determine if it's available
  as a dependency in the current project.

  ## Returns

  Returns `true` if Tailwind module is loaded, `false` otherwise.
  """
  @spec installed? :: boolean
  def installed? do
    case Code.ensure_loaded(Tailwind) do
      {:module, Tailwind} ->
        true

      _fallback ->
        false
    end
  end
end
