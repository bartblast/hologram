alias Hologram.Benchmarks.Fixtures.Page1
alias Hologram.Commons.FileUtils
alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.Compiler.Cache
alias Hologram.Compiler.Tracer
alias Hologram.Reflection

benchmark_tmp_dir = Path.join([Reflection.tmp_dir(), "benchmarks", "mix", "compile.hologram"])

lib_assets_dir = Path.join(Reflection.root_dir(), "assets")
lib_package_json_path = Path.join(lib_assets_dir, "package.json")

assets_dir = Path.join(benchmark_tmp_dir, "assets")
package_json_path = Path.join(assets_dir, "package.json")
build_dir = Path.join(benchmark_tmp_dir, "build")
static_dir = Path.join(benchmark_tmp_dir, "static")
tmp_dir = Path.join(benchmark_tmp_dir, "tmp")

# The file maybe_install_js_deps/2 keeps in the build dir to tell whether the deps are installed.
package_json_digest_path = Path.join(build_dir, "package_json_digest.bin")

opts = [
  assets_dir: assets_dir,
  build_dir: build_dir,
  esbuild_bin_path: Path.join([assets_dir, "node_modules", ".bin", "esbuild"]),
  force?: true,
  js_dir: Path.join(lib_assets_dir, "js"),
  static_dir: static_dir,
  tmp_dir: tmp_dir
]

# The deps are installed once, outside every scenario: no scenario measures the install -
# Hologram.Compiler.maybe_install_js_deps/2 has a benchmark of its own.
FileUtils.recreate_dir(benchmark_tmp_dir)
File.mkdir!(assets_dir)
File.mkdir!(build_dir)
File.cp!(lib_package_json_path, package_json_path)
Compiler.maybe_install_js_deps(assets_dir, build_dir)

package_json_digest = File.read!(package_json_digest_path)

# A build lib dir with one manifest, which the two scenarios with Hologram off read: an edit is faked
# by rewriting the manifest, which the real build's manifests must not be.
build_lib_dir = Path.join(benchmark_tmp_dir, "build_lib")
manifest_dir = Path.join([build_lib_dir, "hologram", ".mix"])
manifest_path = Path.join(manifest_dir, "compile.elixir")
File.mkdir_p!(manifest_dir)
File.write!(manifest_path, "manifest 1")

off_opts =
  opts
  |> Keyword.put(:build_lib_dir, build_lib_dir)
  |> Keyword.put(:force?, false)

# Hologram is on in every scenario but the two that say otherwise. The suite runs in dev, where the
# task treats an unset flag as Hologram off, so an unforced run would take that path instead of the
# skip it is meant to measure.
System.put_env("HOLOGRAM_START", "1")

# The six states a compile is run in.
#
# Cold: nothing on disk but the deps and nothing kept in the VM, as the first build of a project.
# The task keeps its call graph, its IR and the state of every bundle between compiles in one VM,
# so emptying the build dir is not enough - the cache is reset too.
#
# Nothing changed, new VM: a mix command run from a shell with no module changed. The task reads
# the record of what the last finished compile was built from, finds it unchanged and skips.
#
# Nothing changed, same VM: the compile a running dev server makes with no module changed. Forced
# past the skip, it goes through every step and keeps everything.
#
# One page edited, same VM: the compile a running dev server makes after a save of one page, the
# live reload loop. The graph is patched, the data layer is derived again and the page's bundle is
# rebuilt.
#
# Nothing changed, Hologram off: a mix command in dev or test without HOLOGRAM_START, with no module
# changed. The task never compiles there, reads the record of the manifests the data model was last
# validated against, finds it unchanged and validates nothing.
#
# A module changed, Hologram off: the same command after an edit. The manifest of the edited
# module's application moved, so the task lists the entity types and roles from the beams and
# validates the data model.
Benchee.run(
  %{
    "cold" =>
      {fn opts ->
         Mix.Tasks.Compile.Hologram.run(opts)
       end,
       before_each: fn _input ->
         FileUtils.recreate_dir(build_dir)
         FileUtils.recreate_dir(static_dir)
         FileUtils.recreate_dir(tmp_dir)

         # Put back, since the build dir it lives in was just emptied: the deps are in place.
         File.write!(package_json_digest_path, package_json_digest)

         Cache.reset()

         opts
       end},
    "nothing changed, new VM" =>
      {fn opts ->
         Mix.Tasks.Compile.Hologram.run(opts)
       end,
       before_scenario: fn _input ->
         # A finished compile leaves the record the skip reads.
         Mix.Tasks.Compile.Hologram.run(opts)

         unforced_opts = Keyword.put(opts, :force?, false)

         # The scenario is the skip, so a run that compiles instead fails here rather than being
         # measured as one.
         Cache.reset()
         :noop = Mix.Tasks.Compile.Hologram.run(unforced_opts)

         unforced_opts
       end,
       before_each: fn unforced_opts ->
         # A new VM has nothing kept, and the skip is taken only by the first compile in a VM.
         Cache.reset()

         unforced_opts
       end},
    "nothing changed, same VM" =>
      {fn opts ->
         Mix.Tasks.Compile.Hologram.run(opts)
       end,
       before_scenario: fn _input ->
         Mix.Tasks.Compile.Hologram.run(opts)

         opts
       end},
    "one page edited, same VM" =>
      {fn opts ->
         Mix.Tasks.Compile.Hologram.run(opts)
       end,
       before_scenario: fn _input ->
         Mix.Tasks.Compile.Hologram.run(opts)

         opts
       end,
       before_each: fn opts ->
         %{module_info_plt: module_info_plt} = Cache.get()

         # A running VM sees an edit as a module the compiler reports whose beam has another
         # digest than the kept one. The compile reads the beam again and keeps its true digest,
         # so the edit is faked before every run.
         info = PLT.get!(module_info_plt, Page1)
         PLT.put(module_info_plt, Page1, %{info | digest: "edited"})

         bytecode =
           Page1
           |> :code.which()
           |> File.read!()

         Tracer.trace({:on_module, bytecode, :none}, %Macro.Env{module: Page1})

         opts
       end},
    "nothing changed, Hologram off" =>
      {fn off_opts ->
         Mix.Tasks.Compile.Hologram.run(off_opts)
       end,
       before_scenario: fn _input ->
         System.delete_env("HOLOGRAM_START")

         # A validation leaves the record the skip reads.
         :noop = Mix.Tasks.Compile.Hologram.run(off_opts)

         off_opts
       end,
       after_scenario: fn _input ->
         System.put_env("HOLOGRAM_START", "1")
       end},
    "a module changed, Hologram off" =>
      {fn off_opts ->
         Mix.Tasks.Compile.Hologram.run(off_opts)
       end,
       before_scenario: fn _input ->
         System.delete_env("HOLOGRAM_START")

         off_opts
       end,
       before_each: fn off_opts ->
         # A compile of a module rewrites its application's manifest, so a rewritten manifest is
         # what the task sees of an edit.
         File.write!(manifest_path, "manifest #{System.unique_integer([:positive])}")

         off_opts
       end,
       after_scenario: fn _input ->
         System.put_env("HOLOGRAM_START", "1")
       end}
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "mix compile.hologram", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
