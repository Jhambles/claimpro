import nextPlugin from "eslint-config-next";

// eslint-config-next 16+ exports a native flat config (an array of config
// objects), so no FlatCompat/legacy-shim layer is needed here â€” this repo
// never had an .eslintrc at all before this, so there's no legacy config to
// migrate, just a fresh flat config to add.
export default [
  ...nextPlugin,
  {
    ignores: [
      "node_modules/**",
      ".next/**",
      "src/generated/**",
      "src/services/__tests__/**",
      "src/lib/__tests__/**",
      "src/lib/__mocks__/**",
      "coverage/**",
    ],
  },
];
