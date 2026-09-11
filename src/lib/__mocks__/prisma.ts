// Referenced only via jest.config.js's moduleNameMapper, never imported by
// application code. Keeps unit tests from ever instantiating a real
// PrismaClient â€” every service under test is constructed with fake
// repositories, so the real DB client should never be touched here.
export const prisma = new Proxy(
  {},
  {
    get() {
      throw new Error(
        "The real Prisma client was reached during a unit test. Inject a fake repository instead of relying on the default PrismaClient-backed one."
      );
    },
  }
);
