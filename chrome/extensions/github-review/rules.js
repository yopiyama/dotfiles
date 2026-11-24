(() => {
  const defaults = {
    // *.gen.* also matches generator inputs such as buf.gen.yaml.
    generated: ["**/gen/**", "**/generated/**", "**/__generated__/**", "**/*.pb.go", "**/*_grpc.pb.go", "**/*.pb.ts", "**/*_pb.ts", "**/*_pb.js", "**/*.gen.go", "**/*.gen.ts", "**/*.gen.tsx", "**/*.gen.js", "**/*.generated.*", "**/*_generated.*", "**/*_gen.go", "**/*.sql.go", "**/*.mock.go", "**/*_enumer.go"],
    definitions: ["**/*.proto", "**/*.sql", "**/*.graphql", "**/*.gql", "**/openapi.yaml", "**/openapi.yml", "**/swagger.yaml", "**/swagger.yml", "**/*.openapi.yaml", "**/*.openapi.yml", "**/api-schema.yaml", "**/api-schema.yml"],
    tests: ["**/*_test.go", "**/*.test.*", "**/*.spec.*", "**/test/**", "**/tests/**", "**/__tests__/**", "**/testutil/**", "**/testdata/**", "**/testcase/**", "**/mock/**", "**/mocks/**", "**/test_*.py", "**/*_test.py", "**/e2e/runn/**", "**/e2e/playwright/**", "**/load-test/scenario/**"],
    implementation: ["**/*.go", "**/*.ts", "**/*.tsx", "**/*.js", "**/*.jsx", "**/*.mjs", "**/*.cjs", "**/*.py", "**/*.rs", "**/*.rb", "**/*.java", "**/*.kt", "**/*.swift", "**/*.c", "**/*.h", "**/*.cpp", "**/*.cs", "**/*.vue", "**/*.svelte", "**/*.lua", "**/*.css", "**/*.scss", "**/*.sass", "**/*.less", "**/*.html", "**/*.htm", "**/*.tmpl", "**/*.sh"]
  };
  const groups = [
    ["definitions", "定義"], ["implementation", "実装"], ["tests", "テスト"],
    ["other", "その他"], ["generated", "生成ファイル"]
  ];
  // * matches one path component; ** matches any depth; **/ also matches root.
  function glob(pattern) {
    let source = "^";
    for (let i = 0; i < pattern.length; i++) {
      const char = pattern[i];
      if (char === "*" && pattern[i + 1] === "*") {
        if (pattern[i + 2] === "/") { source += "(?:.*/)?"; i += 2; }
        else { source += ".*"; i++; }
      } else if (char === "*") source += "[^/]*";
      else if (char === "?") source += "[^/]";
      else source += char.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");
    }
    return new RegExp(source + "$");
  }
  function normalize(value) {
    return Object.fromEntries(Object.entries(defaults).map(([key, fallback]) => [
      key, Array.isArray(value?.[key]) && value[key].every(p => typeof p === "string")
        ? value[key].map(p => p.trim()).filter(Boolean) : [...fallback]
    ]));
  }
  function classifier(value) {
    const rules = Object.fromEntries(Object.entries(normalize(value)).map(([key, patterns]) => [key, patterns.map(glob)]));
    return (path, generated = false) => {
      if (generated || rules.generated.some(rule => rule.test(path))) return "generated";
      for (const key of ["definitions", "tests", "implementation"]) {
        if (rules[key].some(rule => rule.test(path))) return key;
      }
      return "other";
    };
  }
  function repository(pathname) {
    return pathname.match(/^\/([^/]+\/[^/]+)\/pull\/\d+\/(?:changes|files)(?:\/|$)/)?.[1] ?? null;
  }
  const api = { defaults, groups, glob, normalize, classifier, repository };
  globalThis.GitHubReviewRules = api;
  if (typeof module !== "undefined") module.exports = api;
})();
