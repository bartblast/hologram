defmodule Hologram.MixProjectTest do
  # Not async: Mix.Project.in_project/4 changes the global Mix project stack.
  use Hologram.Test.BasicCase, async: false

  describe "application/0" do
    test "in Hologram's own repo" do
      assert Hologram.MixProject.application() == [extra_applications: [:logger]]
    end

    # Mix gives a dependency's project the expanded lockfile of the project that depends on it.
    test "in a project that depends on Hologram" do
      app_dir = Path.join(@fixtures_dir, "app_with_hologram_dep")
      post_config = [lockfile: Path.join(app_dir, "mix.lock")]

      result =
        Mix.Project.in_project(:app_with_hologram_dep_fixture, app_dir, post_config, fn _module ->
          Hologram.MixProject.application()
        end)

      assert result == [mod: {Hologram.Application, []}, extra_applications: [:logger]]
    end
  end
end
