defmodule App1.ToolingTest do
  # Shells out to nested mix invocations that share the umbrella _build
  # and write to the umbrella root - keep serialized.
  use ExUnit.Case, async: false

  @umbrella_root Path.expand("../..", File.cwd!())

  # HOLOGRAM_START is inherited from Hologram.Test.setup/0 - unset it so
  # nested mix invocations don't trigger Hologram compiler runs.
  @clean_env [{"HOLOGRAM_START", nil}]

  test "mix holo.gen.agents_md writes rules sourced from the Hologram dep at the cwd" do
    agents_path = Path.join(@umbrella_root, "AGENTS.md")
    File.rm(agents_path)
    on_exit(fn -> File.rm(agents_path) end)

    {_output, exit_status} =
      System.cmd("mix", ["holo.gen.agents_md"], cd: @umbrella_root, env: @clean_env)

    assert exit_status == 0

    usage_rules_path = Path.join(@umbrella_root, "deps/hologram/usage-rules.md")
    usage_rules = File.read!(usage_rules_path)

    content = File.read!(agents_path)
    assert content =~ "<!-- hologram-start -->"
    assert content =~ String.trim(usage_rules)
  end

  test "mix holo.routes lists pages from all umbrella child apps" do
    {output, exit_status} =
      System.cmd("mix", ["holo.routes"], cd: @umbrella_root, env: @clean_env)

    assert exit_status == 0

    assert output =~ "/app-3"
    assert output =~ "/npm-import"
    assert output =~ "App1.HomePage"
    assert output =~ "App3.Page"
  end

  test "live reload watches source dirs across all umbrella child apps" do
    script = "IO.inspect(Hologram.LiveReload.watched_dirs())"

    {output, exit_status} =
      System.cmd("mix", ["eval", script], cd: @umbrella_root, env: @clean_env)

    assert exit_status == 0

    assert output =~ Path.join(@umbrella_root, "apps/app_1/app")
    assert output =~ Path.join(@umbrella_root, "apps/app_1/lib")
    assert output =~ Path.join(@umbrella_root, "apps/app_2/lib")
    assert output =~ Path.join(@umbrella_root, "apps/app_3/app")
  end
end
