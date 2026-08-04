import globals from "globals";
import path from "node:path";
import {fileURLToPath} from "node:url";
import js from "@eslint/js";
import {FlatCompat} from "@eslint/eslintrc";

const __filename = fileURLToPath(import.meta.url);

const __dirname = path.dirname(__filename);

const compat = new FlatCompat({
  baseDirectory: __dirname,
  recommendedConfig: js.configs.recommended,
  allConfig: js.configs.all,
});

export default [
  {
    // Vendored third-party code is kept byte-identical to upstream, so it is neither ours to
    // restyle nor ours to lint. It also carries eslint-disable directives for plugins this config
    // does not load, which are themselves reported as errors.
    ignores: ["**/js/vendor/**"],
  },
  ...compat.extends("eslint:recommended"),
  {
    languageOptions: {
      ecmaVersion: "latest",
      globals: {
        ...globals.browser,
        ...globals.mocha,
        ...globals.node,
        Elixir_Code: "readonly",
        Elixir_Enum: "readonly",
        Elixir_Exception: "readonly",
        Elixir_Hologram_Router_Helpers: "readonly",
        Elixir_Kernel: "readonly",
        Elixir_Macro: "readonly",
        Elixir_Map: "readonly",
        Elixir_String_Chars: "readonly",
        Erlang: "readonly",
        Erlang_Binary: "readonly",
        Erlang_Code: "readonly",
        Erlang_Elixir_Aliases: "readonly",
        Erlang_Elixir_Locals: "readonly",
        Erlang_Filename: "readonly",
        Erlang_Lists: "readonly",
        Erlang_Maps: "readonly",
        Erlang_Math: "readonly",
        Erlang_Os: "readonly",
        Erlang_Persistent_Term: "readonly",
        Erlang_Rand: "readonly",
        Erlang_Re: "readonly",
        Erlang_Sets: "readonly",
        Erlang_Unicode: "readonly",
      },
      sourceType: "module",
    },
    rules: {
      "no-unused-vars": [
        "error",
        {
          argsIgnorePattern: "^_",
          varsIgnorePattern: "^_",
        },
      ],
    },
  },
  {
    files: ["**/.eslintrc.{js,cjs}"],
    languageOptions: {
      ecmaVersion: 5,
      globals: {
        ...globals.node,
      },
      sourceType: "commonjs",
    },
  },
];
