alias Hologram.Commons.FileUtils
alias Hologram.Commons.Reflection
alias Hologram.Compiler

without_cache_tmp_dir =
  Path.join([Reflection.tmp_dir(), "compiler", "maybe_install_js_deps_without_cache"])

without_cache_assets_dir = Path.join(without_cache_tmp_dir, "assets")
without_cache_build_dir = Path.join(without_cache_tmp_dir, "build")

with_cache_tmp_dir =
  Path.join([Reflection.tmp_dir(), "compiler", "maybe_install_js_deps_with_cache"])

with_cache_assets_dir = Path.join(with_cache_tmp_dir, "assets")
with_cache_build_dir = Path.join(with_cache_tmp_dir, "build")

lib_package_json_path = Path.join([Reflection.root_dir(), "assets", "package.json"])
without_cache_package_json_path = Path.join(without_cache_assets_dir, "package.json")
with_cache_package_json_path = Path.join(with_cache_assets_dir, "package.json")

# Setup "with cache" case
FileUtils.recreate_dir(with_cache_tmp_dir)
File.mkdir!(with_cache_assets_dir)
File.mkdir!(with_cache_build_dir)
File.cp!(lib_package_json_path, with_cache_package_json_path)
Compiler.maybe_install_js_deps(with_cache_assets_dir, with_cache_build_dir)

Benchee.run(
  %{
    "without cache" => fn _input ->
      Compiler.maybe_install_js_deps(without_cache_assets_dir, without_cache_build_dir)
    end,
    "with cache" => fn _input ->
      Compiler.maybe_install_js_deps(with_cache_assets_dir, with_cache_build_dir)
    end
  },
  before_each: fn _input ->
    # Setup "without cache" case
    FileUtils.recreate_dir(without_cache_tmp_dir)
    File.mkdir!(without_cache_assets_dir)
    File.mkdir!(without_cache_build_dir)

    File.cp!(lib_package_json_path, without_cache_package_json_path)

    System.cmd("npm", ["cache", "clean", "--force"])
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "maybe_install_js_deps/2", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
