/** @type {import('jest').Config} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/tests"],
  testMatch: ["**/*.test.ts"],
  transform: {
    "^.+\\.tsx?$": [
      "ts-jest",
      {
        tsconfig: {
          module: "commonjs",
          target: "ES2022",
          lib: ["ES2022"],
          strict: true,
          esModuleInterop: true,
          skipLibCheck: true,
        },
      },
    ],
  },
  moduleNameMapper: {
    // Map well-known npm packages to hand-rolled test stubs
    "^@azure/functions$": "<rootDir>/tests/__mocks__/@azure/functions.ts",
    "^@anthropic-ai/sdk$": "<rootDir>/tests/__mocks__/@anthropic-ai/sdk.ts",
    // Map internal shared modules — the regex must match the resolved path
    // Jest resolves relative imports to absolute paths first, so we match by filename
    ".*/shared/cosmos(\\.ts)?$": "<rootDir>/tests/__mocks__/cosmos.ts",
    ".*/shared/auth(\\.ts)?$": "<rootDir>/tests/__mocks__/auth.ts",
  },
};
