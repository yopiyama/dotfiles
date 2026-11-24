const { test } = require("node:test");
const assert = require("node:assert/strict");
const rules = require("../rules.js");

test("definition, production, tests and generated files have distinct categories", () => {
  const classify = rules.classifier();
  for (const [path, expected] of [
    ["api/user.proto", "definitions"], ["queries/users.sql", "definitions"],
    ["usecase.go", "implementation"], ["user/usecase_test.go", "tests"],
    ["ui/auth.spec.tsx", "tests"], ["tests/helper.ts", "tests"],
    ["gen/user_test.go", "generated"], ["api/user.pb.go", "generated"],
    ["queries/users.sql.go", "generated"], ["README.md", "other"],
    ["general/engine.go", "implementation"], ["genesis/main.go", "implementation"]
  ]) assert.equal(classify(path), expected, path);
  assert.equal(classify("arbitrary.go", true), "generated");
});
test("globs handle root, nested paths and literal regex characters", () => {
  assert.ok(rules.glob("**/*.proto").test("user.proto"));
  assert.ok(rules.glob("**/*.proto").test("a/b/user.proto"));
  assert.ok(!rules.glob("api/*.proto").test("api/nested/user.proto"));
  assert.ok(rules.glob("**/[id]+(a).ts").test("ui/[id]+(a).ts"));
  assert.ok(!rules.glob("**/*.pb.go").test("userXpbXgo"));
});
test("repository rules replace defaults and permit disabling a category", () => {
  const classify = rules.classifier({ generated: ["custom/**"], tests: [] });
  assert.equal(classify("custom/service.go"), "generated");
  assert.equal(classify("gen/service.go"), "implementation");
  assert.equal(classify("service_test.go"), "implementation");
  assert.equal(classify("service.proto"), "definitions");
});
test("only PR changes/files routes are active, including commit comparisons", () => {
  assert.equal(rules.repository("/owner/repo/pull/123/changes"), "owner/repo");
  assert.equal(rules.repository("/owner/repo/pull/123/files/abc..def"), "owner/repo");
  for (const path of ["/owner/repo/pull/123", "/owner/repo/issues/123", "/owner/repo/pull/123/changes-extra"])
    assert.equal(rules.repository(path), null);
});
test("generator inputs remain visible while generated Go and TypeScript outputs are hidden", () => {
  const classify = rules.classifier();
  for (const path of ["buf.gen.yaml", "proto/buf.gen.yaml", "docs/buf.gen.yaml", "openapi/config.yaml"])
    assert.equal(classify(path), "other", path);
  for (const path of ["api/user.gen.go", "api/user.gen.ts", "api/client.mock.go", "model/status_enumer.go", "db/query_gen.go"])
    assert.equal(classify(path), "generated", path);
  assert.equal(classify("service/mock/generate.go"), "tests");
  assert.equal(classify("service/mock/storage.mock.impl.go"), "tests");
});
test("test helpers and application assets have useful default categories", () => {
  const classify = rules.classifier();
  for (const path of ["backend/testutil/assertions.go", "testdata/user.json", "suite/testcase/get.yml"])
    assert.equal(classify(path), "tests", path);
  for (const path of ["redis/script.lua", "view/login.css", "view/login.html.tmpl", "view/index.html", "scripts/run.sh"])
    assert.equal(classify(path), "implementation", path);
  assert.equal(classify("openapi.yaml"), "definitions");
  assert.equal(classify("api/service.openapi.yml"), "definitions");
  assert.equal(classify("db/migrations/001_create_items.up.sql"), "definitions");
});
test("schema filenames and test framework paths work without repository-specific presets", () => {
  const classify = rules.classifier();
  const expected = [
    ["service/mock/client.go", "tests"],
    ["service/mock/generate.go", "tests"],
    ["backend/openapi/api-schema.yaml", "definitions"],
    ["nested/api-schema.yml", "definitions"],
    ["api-schema.yaml", "definitions"],
    ["e2e/runn/helpers/create.yml", "tests"],
    ["app/e2e/playwright/fixtures/item.ts", "tests"],
    ["load-test/scenario/search/main.ts", "tests"],
    ["e2e/tools/src/App.tsx", "implementation"],
    ["e2e/playwright/helpers/gen/item_pb.ts", "generated"],
    ["e2e/playwright/buf.gen.yaml", "tests"],
    ["db/migrations/001_create_items.up.sql", "definitions"]
  ];
  for (const [path, group] of expected) assert.equal(classify(path), group, path);
});
test("local settings can identify unsuffixed outputs without changing shared defaults", () => {
  const mock = "backend/mock/client.go";
  assert.equal(rules.classifier()(mock), "tests");
  const classify = rules.classifier({ generated: [mock], tests: [] });
  assert.equal(classify(mock), "generated");
  assert.equal(classify("backend/mock/generate.go"), "implementation");
  assert.equal(classify("e2e/playwright/fixtures/setup.ts"), "implementation");
  assert.equal(classify("backend/openapi/api-schema.yaml"), "definitions");
  const value = rules.normalize();
  value.generated.length = 0;
  assert.equal(rules.classifier()("api/client.mock.go"), "generated");
});
