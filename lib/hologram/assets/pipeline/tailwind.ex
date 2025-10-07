defmodule Hologram.Assets.Pipeline.Tailwind do
  def bundle(asset, context) do
    basename = Path.basename(asset.source_path, ".css")
    bundle_path = Path.join(context.css_dist_dir, "#{basename}.css")

    args = [
      "--input=#{asset.source_path}",
      "--output=#{bundle_path}"
    ]

    profile = String.to_atom(basename)
    previous_profile_config = Application.get_env(:tailwind, profile)

    Application.put_env(:tailwind, profile,
      args: args,
      cd: Path.dirname(context.assets_dir)
    )

    try do
      # If Tailwind is not installed, the project will fail to compile
      # when the Tailwind module is explicitly called.
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

  def installed? do
    case Code.ensure_loaded(Tailwind) do
      {:module, Tailwind} ->
        true

      _fallback ->
        false
    end
  end
end
