describe("validateEnv", () => {
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    jest.resetModules();
    process.env = { ...ORIGINAL_ENV };
  });

  afterAll(() => {
    process.env = ORIGINAL_ENV;
  });

  it("throws a clear error listing every missing required variable", () => {
    delete process.env.DATABASE_URL;
    delete process.env.NEXTAUTH_SECRET;
    process.env.NEXTAUTH_URL = "http://localhost:3000";

    const { validateEnv } = require("@/lib/env");
    expect(() => validateEnv()).toThrow(/DATABASE_URL/);
    expect(() => validateEnv()).toThrow(/NEXTAUTH_SECRET/);
  });

  it("does not throw when all required variables are present", () => {
    process.env.DATABASE_URL = "postgresql://x";
    process.env.NEXTAUTH_SECRET = "secret";
    process.env.NEXTAUTH_URL = "http://localhost:3000";

    const { validateEnv } = require("@/lib/env");
    expect(() => validateEnv()).not.toThrow();
  });

  it("warns (but does not throw) for missing optional variables", () => {
    process.env.DATABASE_URL = "postgresql://x";
    process.env.NEXTAUTH_SECRET = "secret";
    process.env.NEXTAUTH_URL = "http://localhost:3000";
    delete process.env.PAYMONGO_SECRET_KEY;
    const warnSpy = jest.spyOn(console, "warn").mockImplementation(() => {});

    const { validateEnv } = require("@/lib/env");
    validateEnv();
    expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining("PAYMONGO_SECRET_KEY"));
    warnSpy.mockRestore();
  });
});
